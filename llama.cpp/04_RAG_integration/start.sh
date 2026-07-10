#!/bin/env bash

./build-cuda/bin/llama-server \
            -hf google/gemma-4-26B-A4B-it-qat-q4_0-gguf\
            -ngl 999 \
            -c 65536 \
            -n 8192 \
            --context-shift \
            --cache-type-k turbo4 \
            --cache-type-v turbo4 \
            -fa on \
            -t 12 \
            -b 1024 -ub 1024 \
            --host 127.0.0.1 \
            --port 8080 \
            --cpu-moe \
            --no-warmup \
            --model-draft ./models/gemma4-draft/gemma-4-26B-A4B-it-qat-assistant-MTP-Q8_0.gguf \
            --spec-type draft-mtp \
            --spec-draft-n-max 2 \
            --spec-draft-n-min 0 \
            -ngld all \
            --device-draft CUDA0 \
            -ctkd q8_0 \
            -ctvd q8_0 \
            --tools all\
            --jinja\
            --webui-mcp-proxy \
            --no-mmap

# --tools read_file,file_glob_search,grep_search,get_datetime \
# # I am satisfied for now .. 😇
