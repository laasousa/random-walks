module InfectionKalman

using DataFrames
using Distributions
using ForwardDiff
using LinearAlgebra
using Optim

export fit

function obj(pvar::Vector, z, w; γ::Float64 = 365.25 / 9, dt::Float64 = 0.00273224, ι::Float64 = 0., η::Float64 = 365.25 / 4, N::Float64 = 7e6, ρ1::Float64 = 0.4, just_nll::Bool = true, betasd::Float64 = 0.5, rzzero::Float64 = 1e6, a::Float64 = 1., vif::Float64 = 10.)
    # prior for time 0
    l0 = pvar[1]
    y0 = l0 * γ / η
    x0 = [N - l0 - y0; l0; y0; 0]
    p0 = [1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 0]
    
    τ = pvar[2]

    #println(pvar)
    dstate = size(x0, 1)

    # cyclic observation matrix
    h = [0 0 0 ρ1]
    
    dobs = 1
    r = Matrix(undef, dobs, dobs)

    # filter (assuming first observation at time 1)
    nobs = length(z)

    Σ = Array{eltype(pvar)}(undef, dobs, dobs, nobs)
    ytkkmo = Array{eltype(pvar)}(undef, dobs, nobs)
    k = Array{eltype(pvar)}(undef, dstate, nobs)
    xkk = Array{eltype(pvar)}(undef, dstate, nobs)
    xkkmo = Array{eltype(pvar)}(undef, dstate, nobs)
    pkk = Array{eltype(pvar)}(undef, dstate, dstate, nobs)
    pkkmo = Array{eltype(pvar)}(undef, dstate, dstate, nobs)
    
    bvec = pvar[3:end]
    @assert length(bvec) == nobs "length of bvec should equal number of observations"
    
    for i in 1:nobs
        β = bvec[i]
        if i == 1
            xlast =  x0
            plast = p0
        else
            xlast = xkk[:,i - 1]
            plast = pkk[:,:,i-1]
        end
        
        x = xlast[1]
        l = xlast[2]
        y = xlast[3]
        xlast[4] = 0
        plast[4,:] .= 0
        plast[:,4] .= 0
        vf = [-β*x*y/N - ι*x, β*x*y/N + ι*x - η*l, η*l - γ*y, γ*y]
        xnext = xlast + dt * vf
        
        for j in 1:dstate
            if xnext[j] < 0
                xnext[j] = 0
            end
        end
        xkkmo[:,i] = xnext
        
        f = [0, (β*x/N*y/N + ι*x/N)*vif, η*l/N, γ*y/N]
        
        q = [  f[1]+f[2]     -f[2]            0      0
                   -f[2] f[2]+f[3]        -f[3]      0
                       0     -f[3]    f[3]+f[4]  -f[4]
                       0         0        -f[4]   f[4]]
                       
        jac= [-β*y/N    0    -β*x/N     0
              β*y/N   -η     β*x/N     0
                  0    η        -γ     0
                  0    0         γ     0]
        
        dp = jac * plast + plast * jac' + q * N
        pkkmo[:,:,i] = plast + dp * dt
        
        if z[i][1] < 1
          r[1,1] = τ * rzzero
        else
          r[1,1] = τ
        end
        Σ[:,:,i] = h * pkkmo[:,:,i] * h' + r
        k[:,i] = pkkmo[:,:,i] * h' / Σ[:,:,i]
        ytkkmo[:,i] = z[i] - h * reshape(xkkmo[:,i], dstate, 1)
        xkk[:,i] = reshape(xkkmo[:,i], dstate, 1) + reshape(k[:,i], dstate, 1) * ytkkmo[:,i]
        pkk[:,:,i] = (I - reshape(k[:,i], dstate, 1) * h) * pkkmo[:,:,i]
    end
    
    jumpdensity = Normal(0, betasd)
    dbeta = [(bvec[i] - γ) - a * (bvec[i - 1] - γ)  for i in 2:length(bvec)]
    statsd = (betasd ^ 2 / (1 - a^2)) ^ 0.5
    rwlik = logpdf(Normal(γ, statsd), bvec[1])
    for diff in dbeta
        rwlik += logpdf(jumpdensity, diff)
    end
    
    nll = 0.5 * (sum(ytkkmo[1,:] .^2 ./ Σ[1,1,:] + map(log, Σ[1,1,:])) + nobs * log(2 * pi)) - rwlik
    if just_nll
       return nll
    else
       return nll, ytkkmo, Σ, xkkmo, pkkmo, pkk
    end
end

function hess(par, z, w)
    @time h = ForwardDiff.hessian(pvar -> obj(pvar, z, w), par)
    h
end

function fit(cdata, pdata; detailed_results::Bool = false, hessian::Bool = false, time_limit = 600, show_trace::Bool = false, betasd::Float64 = 1., N::Float64 = 1e7, a::Float64 = 1.) 

    wsize = size(pdata)[1] - 2
    z = [[el] for el in cdata.smooth[end-wsize+1:end]]
    w = [el for el in cdata.wday[end-wsize+1:end]]

    res = optimize(pvar -> obj(pvar, z, w; betasd = betasd, N = N, a = a), pdata.lower, pdata.upper, pdata.init, Fminbox(LBFGS()), Optim.Options(show_trace = show_trace, time_limit = time_limit); autodiff = :forward)

    if hessian 
        h = hess(res.minimizer, z, w)
        res = [res, h]
    end
    
    if detailed_results
        n, r, s, x, pk, pkk = obj(res.minimizer, z, w; just_nll = false)
        res = [res, n, r, s, x, pk, pkk]
    end
    res
end

end