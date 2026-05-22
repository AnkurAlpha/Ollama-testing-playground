import requests

# MODEL = "deepseek-coder-v2:16b"
# You can change to:
MODEL = "qwen2.5-coder:14b"
# MODEL = "phi4-reasoning:plus"

url = "http://localhost:11434/api/chat"

payload = {
    "model": MODEL,
    "stream": False,
    "messages": [
        {
            "role": "system",
            "content": "You are a careful coding assistant. Explain clearly \
                    and write correct code."
        },
        {
            "role": "user",
            "content": """
Write a simple Python function to check whether a string is a palindrome.
Also give 3 test cases.
"""
        }
    ],
    "options": {
        "temperature": 0.2,
        "num_ctx": 4096
    }
}

response = requests.post(url, json=payload, timeout=5000)
response.raise_for_status()

data = response.json()
print(data["message"]["content"])
