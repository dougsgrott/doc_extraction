import azure.functions as func
import logging
import json
import os
from services.doc_intelligence import DocumentParser
from services.db import DatabaseManager
from services.semantic import SemanticAnalyzer

app = func.FunctionApp()

@app.function_name(name="BlobTriggerPDF")
@app.blob_trigger(arg_name="myblob", path="input-pdfs/{name}", connection="AzureWebJobsStorage")
def main(myblob: func.InputStream):
    logging.info(f"Python blob trigger function processed blob \n"
                 f"Name: {myblob.name} \n"
                 f"Blob Size: {myblob.length} bytes")

    try:
        # 1. Initialize the Service
        parser = DocumentParser()

        # 2. Parse the Document
        # We read the stream from the blob and pass it to the parser
        # Note: We read the blob into memory bytes for the SDK
        file_bytes = myblob.read()
        
        logging.info("Sending document to Azure AI Document Intelligence...")
        result = parser.parse_stream(file_bytes)

        # 3. Process Result (Stub for next steps)
        # The 'result' object contains pages, tables, paragraphs, and styles.
        logging.info("Document analysis complete.")
        logging.info(f"Detected {len(result.pages)} pages.")
        
        if result.paragraphs:
            logging.info(f"Extracted {len(result.paragraphs)} paragraphs.")
            # Example: Print the first paragraph content
            logging.info(f"First paragraph snippet: {result.paragraphs[0].content[:50]}...")


        # 2. Convert Azure Result to Dictionary (for JSON storage)
        # The result object is complex; we convert it to a dict for storage.
        # This includes pages, tables, paragraphs, etc.
        extraction_dict = result.as_dict()

        logging.info("Step 2: Generating insights with Azure OpenAI...")
        # Combine all paragraphs into one text string
        full_text = ""
        if result.paragraphs:
            full_text = "\n".join([p.content for p in result.paragraphs])

        analyzer = SemanticAnalyzer()
        semantic_result = analyzer.analyze_text(full_text)

        logging.info(f"Analysis complete. Type identified: {semantic_result.get('document_type', 'Unknown')}")

        # 3. Save to PostgreSQL
        logging.info("Step 3: Saving to Database...")
        db_manager = DatabaseManager()
        
        # Construct a fake URL for reference (or get the real SAS URL if needed)
        account_name = os.environ.get('AzureWebJobsStorage').split(';')[1].split('=')[1]
        blob_url = f"https://{account_name}.blob.core.windows.net/input-pdfs/{myblob.name}"        

        doc_id = db_manager.save_document(
            filename=myblob.name,
            blob_url=blob_url,
            extraction_data=extraction_dict,
            semantic_data=semantic_result
        )

        logging.info(f"Successfully saved document to DB with ID: {doc_id}")
        # TODO: Send text chunks to Azure OpenAI

    except Exception as e:
        logging.error(f"Error processing document {myblob.name}: {str(e)}")
        raise