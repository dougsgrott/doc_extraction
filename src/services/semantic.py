import os
import json
import logging
from openai import AzureOpenAI

class SemanticAnalyzer:
    def __init__(self):
        self.endpoint = os.environ.get("OPENAI_ENDPOINT")
        self.key = os.environ.get("OPENAI_KEY")
        self.deployment = os.environ.get("OPENAI_DEPLOYMENT")
        self.api_version = os.environ.get("OPENAI_API_VERSION", "2024-02-01") # Defaults if missing

        if not self.endpoint or not self.key:
            logging.warning("OpenAI credentials missing.")

        self.client = AzureOpenAI(
            azure_endpoint=self.endpoint,
            api_key=self.key,
            api_version=self.api_version
        )

    def analyze_text(self, text_content: str) -> dict:
        """
        Sends text to Azure OpenAI to extract structured insights.
        """
        system_prompt = """
        You are an AI assistant processing business documents.
        Analyze the provided text and return a VALID JSON object with the following keys:
        - "summary": A 2-sentence summary of the document.
        - "document_type": The type of document (e.g., Invoice, RFP, Contract).
        - "key_entities": A list of strings identifying main companies, people, or products.
        - "action_items": Any next steps or deadlines mentioned.
        
        Ensure the output is pure JSON. Do not include markdown formatting like ```json.
        """

        # Truncate to avoid limits, though GPT-4o handles large context well.
        safe_text = text_content[:20000]

        try:
            response = self.client.chat.completions.create(
                model=self.deployment,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": safe_text}
                ],
                temperature=0.3,
                response_format={"type": "json_object"}
            )
            
            content = response.choices[0].message.content
            return json.loads(content)
        
        except Exception as e:
            logging.error(f"OpenAI Analysis failed: {str(e)}")
            return {"error": "Semantic analysis failed", "details": str(e)}