from openai import OpenAI

MODEL = "deepseek-coder-v2:16b"
# MODEL = "qwen2.5-coder:14b"
# MODEL = "phi4-reasoning:plus"

client = OpenAI(
    base_url="http://localhost:11434/v1/",
    api_key="ollama",  # required by OpenAI client, ignored by Ollama
)

response = client.chat.completions.create(
    model=MODEL,
    messages=[
        {
            "role": "system",
            "content": "You are a careful coding assistant. Explain \
                    clearly and write correct code."
        },
        {
            "role": "user",
            "content": """
Analyze this code. Is there a bug?

def get_item(items, index):
    return items[index]

print(get_item([1, 2, 3], 10))
"""
        }
    ],
    temperature=0.2,
)

print(response.choices[0].message.content)
