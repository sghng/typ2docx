from os import getenv
from pathlib import Path
from typing import Optional

from adobe.pdfservices.operation.auth.service_principal_credentials import (
    ServicePrincipalCredentials,
)
from adobe.pdfservices.operation.exception.exceptions import (
    SdkException,
    ServiceApiException,
    ServiceUsageException,
)
from adobe.pdfservices.operation.pdf_services import PDFServices
from adobe.pdfservices.operation.pdf_services_media_type import PDFServicesMediaType
from adobe.pdfservices.operation.pdfjobs.jobs.export_pdf_job import ExportPDFJob
from adobe.pdfservices.operation.pdfjobs.params.export_pdf.export_pdf_params import (
    ExportPDFParams,
)
from adobe.pdfservices.operation.pdfjobs.params.export_pdf.export_pdf_target_format import (
    ExportPDFTargetFormat,
)
from adobe.pdfservices.operation.pdfjobs.result.export_pdf_result import ExportPDFResult


def export(input: Path, output: Optional[Path] = None):
    client_id = getenv("PDF_SERVICES_CLIENT_ID")
    client_secret = getenv("PDF_SERVICES_CLIENT_SECRET")

    try:
        credentials = ServicePrincipalCredentials(client_id, client_secret)
        service = PDFServices(credentials)

        with open(input, "rb") as f:
            input_stream = f.read()

        input_asset = service.upload(input_stream, PDFServicesMediaType.PDF)
        params = ExportPDFParams(ExportPDFTargetFormat.DOCX)
        job = ExportPDFJob(input_asset, params)
        location = service.submit(job)

        response = service.get_job_result(location, ExportPDFResult)
        result_asset = response.get_result().get_asset()
        output_stream = service.get_content(result_asset)

        output = output or Path(f"{input.stem}.docx")
        with open(output, "wb") as file:
            file.write(output_stream.get_input_stream())

    except (ServiceApiException, ServiceUsageException, SdkException) as e:
        raise RuntimeError(f"Adobe PDFServices API encountered an error: {e}") from e


if __name__ == "__main__":
    export(Path(".typ2docx/a.pdf"))
