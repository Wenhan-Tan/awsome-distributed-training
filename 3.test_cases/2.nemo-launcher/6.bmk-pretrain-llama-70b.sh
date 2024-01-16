#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -exo pipefail
[[ -z "${TARGET_PATH}" ]] \
    && { echo Please set environment variable TARGET_PATH ; exit 1 ; } \
    || echo TARGET_PATH=$TARGET_PATH

################################################################################
# 000: Modify this section to define pre-training configuration: model size,
# number of nodes, max. pre-training steps, job's max. runtime.
################################################################################
## Pre-train llama2-7b on 16 nodes for 5 steps
export MODEL=llama
export MODEL_SIZE=llama2_70b
export NUM_NODES=16
export TIME_LIMIT="7-00:00:00"
export MAX_STEPS=5

declare -a MODEL_ARGS=(
    training.model.tokenizer.model=${TARGET_PATH}/data/llama2/tokenizer.model
    training.model.gc_interval=0

    ## Uncomment below to enable fp8 training (Transformers Engine) on p5 instances (H100 GPUs)
    #training.model.transformer_engine=True
    #training.model.fp8=True
)


################################################################################
# 010: Advance users can modify this stanza to customize benchmarking behavior.
################################################################################
declare -a BMK_ARGS=(
    # Disable validation, as we're only interested to measure the training time.
    training.trainer.limit_val_batches=0.0

    # Disable wandb_logger
    training.exp_manager.create_wandb_logger=False

    # Ignore checkpoints
    training.exp_manager.create_checkpoint_callback=False
    training.exp_manager.resume_if_exists=False

    # https://github.com/NVIDIA/NeMo/pull/6181/files
    training.model.data.data_impl=mock
    training.model.data.data_prefix=[]
)


################################################################################
# 020: Internal settings.
################################################################################
WORKSPACE_CONT=$TARGET_PATH
CONT_RESULT_DIR=${WORKSPACE_CONT}/results-v2
CONT_TOKENIZER_DIR=${WORKSPACE_CONT}/data/bpe

# Dev/test feature (off by default) to force each pre-training run outputs to a separate directory.
: "${BMK_MODE:=0}"
if [[ ${BMK_MODE} -eq 1 ]]; then
    # For debugging: each run has its own output dir.
    TIMESTAMP=$(date +'%Y%m%d-%H%M%Sutc-%N')-$((RANDOM))
    CONT_RESULT_DIR=${CONT_RESULT_DIR}-${TIMESTAMP}

    BMK_ARGS+=(
        base_results_dir=${CONT_RESULT_DIR}
        training.run.dependency=null
    )

    echo "
    ####################
    This run will write to directory ${CONT_RESULT_DIR}
    ####################
    "
fi


################################################################################
# 030: Here we go...
################################################################################
HYDRA_FULL_ERROR=1 python3 $TARGET_PATH/launcher_scripts/main.py \
    stages=[training] \
    training=${MODEL}/${MODEL_SIZE} \
    training.run.time_limit=$TIME_LIMIT \
    training.trainer.num_nodes=$NUM_NODES \
    training.trainer.max_steps=$MAX_STEPS \
    training.trainer.val_check_interval=$MAX_STEPS \
    "${BMK_ARGS[@]}" "${MODEL_ARGS[@]}" "$@"
