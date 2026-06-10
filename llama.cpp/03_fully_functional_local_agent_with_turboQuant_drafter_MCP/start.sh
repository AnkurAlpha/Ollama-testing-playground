#!/bin/env bash

./build/bin/llama-server \
            -hf google/gemma-4-26B-A4B-it-qat-q4_0-gguf\
            -ngl 999 \
            -c 16384 \
            -n 4096 \
            --context-shift \
            --cache-type-k turbo3 \
            --cache-type-v turbo2 \
            -fa on \
            -t 10 \
            -b 128 -ub 128 \
            --host 127.0.0.1 \
            --port 8080 \
            --cpu-moe \
            --no-warmup \
            --spec-type ngram-mod\
            --spec-ngram-mod-n-min 24 \
            --spec-ngram-mod-n-max 64 \
            --tools all\
            --jinja\
            --webui-mcp-proxy
            # --tools read_file,file_glob_search,grep_search,get_datetime \
            # --no-mmap

# # I am satisfied for now .. 😇
