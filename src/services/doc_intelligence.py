import os
from azure.core.credentials import AzureKeyCredential
from azure.ai.documentintelligence import DocumentIntelligenceClient
from azure.ai.documentintelligence.models import AnalyzeResult

class DocumentParser:
    def __init__(self):
        self.endpoint = os.environ.get("DI_ENDPOINT")
        self.key = os.environ.get("DI_KEY")
        
        if not self.endpoint or not self.key:
            raise ValueError("Missing Document Intelligence configuration.")

        self.client = DocumentIntelligenceClient(
            endpoint=self.endpoint, 
            credential=AzureKeyCredential(self.key)
        )

    def parse_stream(self, file_stream) -> AnalyzeResult:
        """
        Sends a file stream to Azure Document Intelligence using the prebuilt-layout model.
        """
        # 'prebuilt-layout' is great for extracting structure, text, and tables
        poller = self.client.begin_analyze_document(
            "prebuilt-layout", 
            file_stream,
            content_type="application/octet-stream"
        )
        
        result: AnalyzeResult = poller.result()
        return result