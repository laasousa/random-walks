#!/usr/bin/env bash

set -e

dvc run \
    -d pull-other-forecasts.R \
    -o other-model-forecasts.rds \
    --force \
    -n pull-archived-forecasts \
    ./pull-other-forecasts.R
    
dvc run \
    -d other-model-forecasts.rds \
    -d CEID-InfectionKalman \
    -d make-trajectory-plots.R \
    -o trajectories-all.png \
    -o trajectories-0.png \
    -o trajectories-1.png \
    -o trajectories-2.png \
    -o trajectories-3.png \
    --force \
    -n make-trajectory-plots \
    ./make-trajectory-plots.R
    
dvc run \
    -d other-model-forecasts.rds \
    -d CEID-InfectionKalman \
    -d analyze-scores.R \
    -o figure \
    -o analyze-scores.md \
    -o analyze-scores.html \
    --force \
    -n analyze-scores \
    'Rscript -e "knitr::spin(\"analyze-scores.R\")"'