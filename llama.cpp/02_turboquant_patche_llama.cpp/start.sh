#!/bin/env bash
#
# -hf bartowski/Qwen_Qwen3-30B-A3B-GGUF:Q2_K\ == useless
# -hf bartowski/Qwen_Qwen3-30B-A3B-GGUF:IQ2_M\ --> only for very small tasks
./build/bin/llama-server \
            -hf ggml-org/gemma-4-26B-A4B-it-GGUF:Q4_K_M\
            -ngl 999 \
            -c 16384 \
            -n 4096 \
            --context-shift\
            --cache-type-k turbo3\
            --cache-type-v turbo2\
            -fa on \
            -t 8\
            -b 512 -ub 512\
            --host 127.0.0.1\
            --port 8080\
            --cpu-moe\
            --no-warmup\
            --tools read_file,file_glob_search,grep_search,get_datetime\
            --webui-mcp-proxy
# --no-mmap\ # 😭 GPU with only 4GB VRAM
