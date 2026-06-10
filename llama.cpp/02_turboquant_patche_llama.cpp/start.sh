#!/bin/env bash

# -hf bartowski/Qwen_Qwen3-30B-A3B-GGUF:Q2_K\ == useless
# -hf bartowski/Qwen_Qwen3-30B-A3B-GGUF:IQ2_M\ --> only for very small tasks
# -hf ggml-org/gemma-4-26B-A4B-it-GGUF:Q4_K_M\
./build/bin/llama-server \
            -hf bartowski/google_gemma-4-26B-A4B-it-GGUF:IQ2_M \
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
            --jinja\
            --tools read_file,file_glob_search,grep_search,get_datetime \
            --webui-mcp-proxy \
            --no-mmap

# I am satisfied for now .. 😇
# current speed for now 23 t/s after choosing a good drafter
# https://github.com/TheTom/llama-cpp-turboquant
