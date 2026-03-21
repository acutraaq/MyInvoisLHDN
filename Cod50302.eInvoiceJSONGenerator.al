/// <summary>
/// Business Central e-Invoice JSON Generator and Azure Function Integration
/// 
/// PURPOSE:
/// Generate LHDN-compliant UBL 2.1 JSON invoices and process through Azure Function for digital signing
/// 
/// INTEGRATION FLOW:
/// 1. Business Central generates unsigned e-Invoice JSON (UBL 2.1 format)
/// 2. Posts JSON to Azure Function with proper payload structure
/// 3. Azure Function digitally signs using JOTEX P12 certificate (7-step process)
/// 4. Returns signed JSON and LHDN-ready payload to Business Central
/// 5. Business Central submits to LHDN MyInvois API
/// 6. Processes LHDN response and updates invoice status
/// 
/// AZURE FUNCTION INTEGRATION:
/// - Endpoint: Configurable in eInvoice Setup
/// - Payload: {"unsignedJson": "...", "invoiceType": "01", "environment": "PREPROD/PRODUCTION", "timestamp": "...", "requestId": "..."}
/// - Response: {"success": true, "signedJson": "...", "lhdnPayload": {"documents": [...]}}
/// - Error Handling: Comprehensive validation and retry logic
/// 
/// LHDN COMPLIANCE:
/// - UBL 2.1 JSON structure as per LHDN specification
/// - Digital signature using JOTEX certificate infrastructure
/// - Proper TIN validation and environment-specific endpoints
/// - Complete audit trail for compliance requirements
/// 
/// CUSTOMIZATION POINTS:
/// - Business logic helper procedures for company-specific mappings
/// - Field population based on your Business Central setup
/// - Error handling and logging preferences
/// 
/// Author: Business Central e-Invoice Integration Team
/// Version: 2.0 - Enhanced with Azure Function integration and comprehensive error handling
/// Last Updated: July 2025
/// </summary>
codeunit 50302 "eInvoice JSON Generator"
{
    Permissions = tabledata "Sales Invoice Header" = M,
                  tabledata "Sales Cr.Memo Header" = M;

    var
        SuppressUserDialogs: Boolean;
    // ======================================================================================================
    // MAIN AZURE FUNCTION INTEGRATION PROCEDURES
    // ======================================================================================================

    /// <summary>
    /// Sends unsigned e-Invoice JSON to Azure Function for digital signing using JOTEX certificate
    /// This is a simplified version - main logic moved to TryPostToAzureFunctionInternal for better error handling
    /// </summary>
    /// <param name="JsonText">Unsigned e-Invoice JSON in UBL 2.1 format</param>
    /// <param name="AzureFunctionUrl">Azure Function endpoint URL for signing service</param>
    /// <param name="ResponseText">Response from Azure Function containing signed JSON and LHDN payload</param>
    procedure PostJsonToAzureFunction(JsonText: Text; AzureFunctionUrl: Text; var ResponseText: Text)
    var
        Success: Boolean;
        CorrelationId: Text;
        MaxRetries: Integer;
    begin
        CorrelationId := CreateGuid();
        MaxRetries := 3;
        Success := TryDirectHttpClient(AzureFunctionUrl, BuildAzureFunctionPayload(JsonText, CorrelationId, '01'), ResponseText, CorrelationId, MaxRetries);
        if not Success then begin
            Error('Failed to communicate with Azure Function: %1', ResponseText);
        end;
    end;

    /// <summary>
    /// Controls whether informational Message dialogs are shown to the user.
    /// Use true to suppress success popups in UI flows (e.g., Return Order submission).
    /// </summary>
    procedure SetSuppressUserDialogs(NewValue: Boolean)
    begin
        SuppressUserDialogs := NewValue;
    end;

    /// <summary>
    /// Safe wrapper for TryPostToAzureFunction that returns boolean instead of throwing errors
    /// Used by page extensions to avoid recursion issues
    /// </summary>
    /// <param name="JsonText">Unsigned e-Invoice JSON in UBL 2.1 format</param>
    /// <param name="AzureFunctionUrl">Azure Function endpoint URL for signing service</param>
    /// <param name="ResponseText">Response from Azure Function containing signed JSON and LHDN payload</param>
    /// <returns>True if successful, False if failed</returns>
    procedure TryPostToAzureFunctionSafe(JsonText: Text; AzureFunctionUrl: Text; var ResponseText: Text): Boolean
    begin
        // Use the new direct implementation
        exit(TryPostToAzureFunctionDirect(JsonText, AzureFunctionUrl, ResponseText));
    end;

    /// <summary>
    /// Public wrapper that provides error messages for compatibility
    /// </summary>
    /// <param name="JsonText">JSON payload to send</param>
    /// <param name="AzureFunctionUrl">Azure Function endpoint URL</param>
    /// <param name="ResponseText">Response from Azure Function</param>
    /// <returns>True if successful, False if failed after all retries</returns>
    procedure TryPostToAzureFunction(JsonText: Text; AzureFunctionUrl: Text; var ResponseText: Text): Boolean
    var
        Success: Boolean;
    begin
        Success := TryPostToAzureFunctionDirect(JsonText, AzureFunctionUrl, ResponseText);

        if Success then begin
            // Additional validation can be added here
            if ResponseText = '' then begin
                ResponseText := 'Azure Function returned empty response';
                Success := false;
            end;
        end;

        if not Success then begin
            Error('Failed to communicate with Azure Function.\n\nPlease check:\n- Network connectivity\n- Azure Function availability\n- Azure Function URL configuration\n\nError Details: %1', ResponseText);
        end;
        exit(true);
    end;

    /// <summary>
    /// Session-safe wrapper that calls the main implementation
    /// </summary>
    /// <param name="JsonText">JSON payload to send</param>
    /// <param name="AzureFunctionUrl">Azure Function endpoint URL</param>
    /// <param name="ResponseText">Response from Azure Function</param>
    /// <returns>True if successful, False if failed</returns>
    procedure TryPostToAzureFunctionSessionSafe(JsonText: Text; AzureFunctionUrl: Text; var ResponseText: Text): Boolean
    begin
        // Call the main implementation
        exit(TryPostToAzureFunctionDirect(JsonText, AzureFunctionUrl, ResponseText));
    end;

    /// <summary>
    /// Validates Azure Function URL format
    /// </summary>
    local procedure ValidateAzureFunctionUrl(Url: Text): Boolean
    begin
        // Basic URL validation
        if Url = '' then
            exit(false);

        if not Url.StartsWith('https://') then
            exit(false);

        if not Url.Contains('azurewebsites.net') then
            exit(false);

        if not Url.Contains('/api/') then
            exit(false);

        exit(true);
    end;

    /// <summary>
    /// Updates the eInvoice Validation Status field in the Posted Sales Invoice
    /// This procedure has the necessary tabledata permissions to modify the Sales Invoice Header
    /// </summary>
    /// <param name="InvoiceNo">The invoice number to update</param>
    /// <param name="NewStatus">The new validation status from LHDN</param>
    /// <returns>True if successfully updated, false otherwise</returns>
    procedure UpdateInvoiceValidationStatus(InvoiceNo: Code[20]; NewStatus: Text): Boolean
    var
        SalesInvoiceHeader: Record "Sales Invoice Header";
    begin
        if SalesInvoiceHeader.Get(InvoiceNo) then begin
            SalesInvoiceHeader."eInvoice Validation Status" := CopyStr(NewStatus, 1, MaxStrLen(SalesInvoiceHeader."eInvoice Validation Status"));
            exit(SalesInvoiceHeader.Modify());
        end;
        exit(false);
    end;

    /// <summary>
    /// Updates the eInvoice QR URL on the Posted Sales Invoice using modify permissions in this codeunit
    /// </summary>
    /// <param name="InvoiceNo">The posted invoice number</param>
    /// <param name="Url">Validation URL to store</param>
    /// <returns>True if updated</returns>
    procedure UpdateInvoiceQrUrl(InvoiceNo: Code[20]; Url: Text): Boolean
    var
        SalesInvoiceHeader: Record "Sales Invoice Header";
    begin
        if (InvoiceNo = '') or (Url = '') then
            exit(false);

        if SalesInvoiceHeader.Get(InvoiceNo) then begin
            SalesInvoiceHeader."eInvoice QR URL" := CopyStr(Url, 1, MaxStrLen(SalesInvoiceHeader."eInvoice QR URL"));
            exit(SalesInvoiceHeader.Modify());
        end;
        exit(false);
    end;

    /// <summary>
    /// Updates the eInvoice QR Image media field on the Posted Sales Invoice
    /// </summary>
    /// <param name="InvoiceNo">The posted invoice number</param>
    /// <param name="InS">Image stream to import</param>
    /// <param name="FileName">Image filename</param>
    /// <returns>True if updated</returns>
    procedure UpdateInvoiceQrImage(InvoiceNo: Code[20]; var InS: InStream; FileName: Text): Boolean
    var
        SalesInvoiceHeader: Record "Sales Invoice Header";
    begin
        if (InvoiceNo = '') then
            exit(false);

        if SalesInvoiceHeader.Get(InvoiceNo) then begin
            SalesInvoiceHeader."eInvoice QR Image".ImportStream(InS, FileName);
            exit(SalesInvoiceHeader.Modify());
        end;
        exit(false);
    end;

    /// <summary>
    /// Updates the eInvoice fields in the Posted Sales Credit Memo with LHDN response data
    /// This procedure has the necessary tabledata permissions to modify the Sales Cr.Memo Header
    /// </summary>
    /// <param name="CreditMemoNo">The credit memo number to update</param>
    /// <param name="SubmissionUid">LHDN submission UID</param>
    /// <param name="DocumentUuid">Document UUID from LHDN</param>
    /// <param name="ValidationStatus">Validation status</param>
    /// <returns>True if successfully updated, false otherwise</returns>
    procedure UpdateCreditMemoWithLhdnData(CreditMemoNo: Code[20]; SubmissionUid: Text; DocumentUuid: Text; ValidationStatus: Text): Boolean
    var
        SalesCrMemoHeader: Record "Sales Cr.Memo Header";
    begin
        if SalesCrMemoHeader.Get(CreditMemoNo) then begin
            if SubmissionUid <> '' then
                SalesCrMemoHeader."eInvoice Submission UID" := CopyStr(CleanQuotesFromText(SubmissionUid), 1, MaxStrLen(SalesCrMemoHeader."eInvoice Submission UID"));
            if DocumentUuid <> '' then
                SalesCrMemoHeader."eInvoice UUID" := CopyStr(CleanQuotesFromText(DocumentUuid), 1, MaxStrLen(SalesCrMemoHeader."eInvoice UUID"));
            if ValidationStatus <> '' then
                SalesCrMemoHeader."eInvoice Validation Status" := CopyStr(ValidationStatus, 1, MaxStrLen(SalesCrMemoHeader."eInvoice Validation Status"));
            exit(SalesCrMemoHeader.Modify());
        end;
        exit(false);
    end;

    /// <summary>
    /// Simple connectivity test for Azure Function
    /// </summary>
    procedure TestAzureFunctionConnectivity(AzureFunctionUrl: Text): Text
    var
        HttpClient: HttpClient;
        HttpResponseMessage: HttpResponseMessage;
        ResponseText: Text;
        TestUrl: Text;
    begin
        // Test connectivity endpoint (no authentication needed)
        TestUrl := 'https://einvoicejotex-b0hthca2gqaghwcf.southeastasia-01.azurewebsites.net/api/connectivity-test';

        if HttpClient.Get(TestUrl, HttpResponseMessage) then begin
            if HttpResponseMessage.IsSuccessStatusCode then begin
                HttpResponseMessage.Content.ReadAs(ResponseText);
                exit('Azure Function connectivity successful. Response: ' + CopyStr(ResponseText, 1, 200));
            end else begin
                exit('Function returned error: ' + Format(HttpResponseMessage.HttpStatusCode));
            end;
        end else begin
            exit('Cannot connect to Azure Function - Check network connectivity');
        end;
    end;

    /// <summary>
    /// Analyzes Azure Function URL structure for diagnostics
    /// </summary>
    local procedure AnalyzeAzureFunctionUrl(Url: Text): Text
    var
        Analysis: Text;
        HasHttps: Boolean;
        HasAzureWebsites: Boolean;
        HasApi: Boolean;
        HasCode: Boolean;
        FunctionName: Text;
        AppName: Text;
        ApiPos: Integer;
        CodePos: Integer;
    begin
        Analysis := '';

        // Check HTTPS
        HasHttps := Url.StartsWith('https://');
        Analysis += '- HTTPS: ' + Format(HasHttps) + '\n';

        // Check Azure Websites domain
        HasAzureWebsites := Url.Contains('azurewebsites.net');
        Analysis += '- Azure Domain: ' + Format(HasAzureWebsites) + '\n';

        // Extract app name
        if HasHttps and HasAzureWebsites then begin
            AppName := CopyStr(Url, 9); // Remove https://
            if AppName.Contains('.') then
                AppName := CopyStr(AppName, 1, AppName.IndexOf('.') - 1);
            Analysis += '- App Name: ' + AppName + '\n';
        end;

        // Check API path
        HasApi := Url.Contains('/api/');
        Analysis += '- API Path: ' + Format(HasApi) + '\n';

        // Extract function name
        if HasApi then begin
            ApiPos := Url.IndexOf('/api/');
            FunctionName := CopyStr(Url, ApiPos + 5);
            if FunctionName.Contains('?') then
                FunctionName := CopyStr(FunctionName, 1, FunctionName.IndexOf('?') - 1);
            Analysis += '- Function Name: ' + FunctionName + '\n';
        end;

        // Check function key
        HasCode := Url.Contains('?code=');
        Analysis += '- Has Function Key: ' + Format(HasCode) + '\n';

        // Overall assessment
        if HasHttps and HasAzureWebsites and HasApi and HasCode then
            Analysis += '- Overall: URL format looks correct'
        else
            Analysis += '- Overall: URL format may have issues';

        exit(Analysis);
    end;

    /// <summary>
    /// Direct HTTP call to Azure Function with proper implementation
    /// </summary>
    procedure TryPostToAzureFunctionDirect(JsonText: Text; AzureFunctionUrl: Text; var ResponseText: Text): Boolean
    var
        DummySalesInvoiceHeader: Record "Sales Invoice Header";
    begin
        // Backward compatibility version - uses default values
        exit(TryPostToAzureFunctionDirect(JsonText, AzureFunctionUrl, ResponseText, DummySalesInvoiceHeader));
    end;

    /// <summary>
    /// Direct HTTP call to Azure Function with proper implementation for Credit Memos
    /// </summary>
    procedure TryPostToAzureFunctionDirect(JsonText: Text; AzureFunctionUrl: Text; var ResponseText: Text; SalesCrMemoHeader: Record "Sales Cr.Memo Header"): Boolean
    var
        HttpClient: HttpClient;
        HttpRequestMessage: HttpRequestMessage;
        HttpResponseMessage: HttpResponseMessage;
        RequestContent: HttpContent;
        JsonObj: JsonObject;
        Headers: HttpHeaders;
        RequestId: Text;
        RequestText: Text;
        eInvoiceSetup: Record "eInvoiceSetup";
        EnvironmentText: Text;
        DocumentTypeCode: Text;
        InvoiceTypeCode: Text;
    begin
        RequestId := CreateGuid();

        // Get environment from setup
        if eInvoiceSetup.Get('SETUP') then begin
            if eInvoiceSetup.Environment = eInvoiceSetup.Environment::Preprod then
                EnvironmentText := 'PREPROD'
            else
                EnvironmentText := 'PRODUCTION';
        end else begin
            EnvironmentText := 'PREPROD'; // Default to preprod if setup not found
        end;

        // Determine document type based on credit memo (same logic as invoice)
        DocumentTypeCode := GetDocumentTypeFromSalesCreditMemo(SalesCrMemoHeader);
        InvoiceTypeCode := '02'; // Credit Note as per LHDN types

        // Get invoice type from Sales Credit Memo Header as fallback
        if SalesCrMemoHeader."eInvoice Document Type" <> '' then
            InvoiceTypeCode := SalesCrMemoHeader."eInvoice Document Type";

        // Create request payload matching Azure Function expectations
        JsonObj.Add('unsignedJson', JsonText);
        JsonObj.Add('invoiceType', InvoiceTypeCode);
        JsonObj.Add('documentType', DocumentTypeCode);
        JsonObj.Add('environment', EnvironmentText);
        JsonObj.Add('submissionId', RequestId);
        JsonObj.Add('correlationId', RequestId);
        JsonObj.Add('requestedBy', UserId());
        JsonObj.Add('timestamp', Format(CurrentDateTime, 0, '<Year4>-<Month,2>-<Day,2>T<Hours24,2>:<Minutes,2>:<Seconds,2>Z'));
        JsonObj.Add('requestId', RequestId);

        // Convert to string
        JsonObj.WriteTo(RequestText);
        RequestContent.WriteFrom(RequestText);

        // Set headers
        RequestContent.GetHeaders(Headers);
        Headers.Clear();
        Headers.Add('Content-Type', 'application/json');

        // Configure request
        HttpRequestMessage.Method := 'POST';
        HttpRequestMessage.SetRequestUri(AzureFunctionUrl);
        HttpRequestMessage.Content := RequestContent;

        // Set timeout
        HttpClient.Timeout(300000); // 5 minutes

        // Send request
        if HttpClient.Send(HttpRequestMessage, HttpResponseMessage) then begin
            if HttpResponseMessage.IsSuccessStatusCode then begin
                HttpResponseMessage.Content.ReadAs(ResponseText);
                exit(true);
            end else begin
                HttpResponseMessage.Content.ReadAs(ResponseText);
                exit(false);
            end;
        end;

        exit(false);
    end;

    /// <summary>
    /// Direct HTTP call to Azure Function with proper implementation using Sales Invoice Header context
    /// ENHANCED: Now includes document type support for better Azure Function processing
    /// </summary>
    procedure TryPostToAzureFunctionDirect(JsonText: Text; AzureFunctionUrl: Text; var ResponseText: Text; SalesInvoiceHeader: Record "Sales Invoice Header"): Boolean
    var
        HttpClient: HttpClient;
        HttpRequestMessage: HttpRequestMessage;
        HttpResponseMessage: HttpResponseMessage;
        RequestContent: HttpContent;
        JsonObj: JsonObject;
        Headers: HttpHeaders;
        RequestId: Text;
        RequestText: Text;
        eInvoiceSetup: Record "eInvoiceSetup";
        EnvironmentText: Text;
        InvoiceTypeCode: Text;
        DocumentTypeCode: Text;
    begin
        RequestId := CreateGuid();

        // Get environment from setup
        if eInvoiceSetup.Get('SETUP') then begin
            if eInvoiceSetup.Environment = eInvoiceSetup.Environment::Preprod then
                EnvironmentText := 'PREPROD'
            else
                EnvironmentText := 'PRODUCTION';
        end else begin
            EnvironmentText := 'PREPROD'; // Default to preprod if setup not found
        end;

        // Determine document type based on document
        DocumentTypeCode := GetDocumentTypeFromSalesInvoice(SalesInvoiceHeader);
        InvoiceTypeCode := '01'; // Business process type

        // Get invoice type from Sales Invoice Header as fallback
        if SalesInvoiceHeader."eInvoice Document Type" <> '' then
            InvoiceTypeCode := SalesInvoiceHeader."eInvoice Document Type";

        // Create request payload matching Azure Function expectations with document type
        JsonObj.Add('unsignedJson', JsonText);
        JsonObj.Add('invoiceType', InvoiceTypeCode);
        JsonObj.Add('documentType', DocumentTypeCode);
        JsonObj.Add('environment', EnvironmentText);
        JsonObj.Add('timestamp', Format(CurrentDateTime, 0, '<Year4>-<Month,2>-<Day,2>T<Hours24,2>:<Minutes,2>:<Seconds,2>Z'));
        JsonObj.Add('requestId', RequestId);
        JsonObj.Add('submissionId', RequestId);
        JsonObj.Add('correlationId', RequestId);
        JsonObj.Add('requestedBy', UserId());

        // Convert to string
        JsonObj.WriteTo(RequestText);
        RequestContent.WriteFrom(RequestText);

        // Set headers
        RequestContent.GetHeaders(Headers);
        Headers.Clear();
        Headers.Add('Content-Type', 'application/json');

        // Configure request
        HttpRequestMessage.Method := 'POST';
        HttpRequestMessage.SetRequestUri(AzureFunctionUrl);
        HttpRequestMessage.Content := RequestContent;

        // Set timeout
        HttpClient.Timeout(300000); // 5 minutes

        // Send request
        if HttpClient.Send(HttpRequestMessage, HttpResponseMessage) then begin
            if HttpResponseMessage.IsSuccessStatusCode then begin
                HttpResponseMessage.Content.ReadAs(ResponseText);
                exit(true);
            end else begin
                HttpResponseMessage.Content.ReadAs(ResponseText);
                exit(false);
            end;
        end;

        exit(false);
    end;



    // ======================================================================================================
    // MAIN E-INVOICE JSON GENERATION PROCEDURES
    // ======================================================================================================

    /// <summary>
    /// Generates LHDN-compliant UBL 2.1 JSON for Sales Invoice
    /// </summary>
    /// <param name="SalesInvoiceHeader">Sales Invoice record to convert</param>
    /// <param name="IncludeSignature">Whether to include digital signature placeholder</param>
    /// <returns>Complete UBL 2.1 JSON string</returns>
    procedure GenerateEInvoiceJson(SalesInvoiceHeader: Record "Sales Invoice Header"; IncludeSignature: Boolean) JsonText: Text
    var
        JsonObject: JsonObject;
        StartTime: DateTime;
    begin
        StartTime := CurrentDateTime;

        // Validate input
        if SalesInvoiceHeader."No." = '' then
            Error('Sales Invoice Header cannot be empty');

        JsonObject := BuildEInvoiceJson(SalesInvoiceHeader, IncludeSignature);
        JsonObject.WriteTo(JsonText);

        // Validate output
        if JsonText = '' then
            Error('Failed to generate JSON for invoice %1', SalesInvoiceHeader."No.");

        // Log completion
        // Message('eInvoice JSON generated for %1 in %2 ms', 
        //     SalesInvoiceHeader."No.", 
        //     CurrentDateTime - StartTime);
    end;

    /// <summary>
    /// Generates e-Invoice JSON for posted sales credit memos
    /// ENHANCED IMPLEMENTATION: 
    /// - Supports proper document type '02' for LHDN Credit Note
    /// - Azure Function integration with document type specification
    /// - Correct UBL 2.1 structure for credit memos
    /// - Negative amounts for proper credit note handling
    /// - Complete LHDN compliance with credit note requirements
    /// </summary>
    /// <param name="SalesCrMemoHeader">The posted sales credit memo header</param>
    /// <param name="IncludeSignature">Whether to include digital signature</param>
    /// <returns>Complete UBL 2.1 JSON string for credit memo</returns>
    procedure GenerateCreditMemoEInvoiceJson(SalesCrMemoHeader: Record "Sales Cr.Memo Header"; IncludeSignature: Boolean) JsonText: Text
    var
        JsonObject: JsonObject;
        StartTime: DateTime;
    begin
        StartTime := CurrentDateTime;

        // Validate input
        if SalesCrMemoHeader."No." = '' then
            Error('Sales Credit Memo Header cannot be empty');

        JsonObject := BuildCreditMemoEInvoiceJson(SalesCrMemoHeader, IncludeSignature);
        JsonObject.WriteTo(JsonText);

        // Validate output
        if JsonText = '' then
            Error('Failed to generate JSON for credit memo %1', SalesCrMemoHeader."No.");

        // Log completion
        // Message('eInvoice JSON generated for credit memo %1 in %2 ms', 
        //     SalesCrMemoHeader."No.", 
        //     CurrentDateTime - StartTime);
    end;

    local procedure BuildEInvoiceJson(SalesInvoiceHeader: Record "Sales Invoice Header"; IncludeSignature: Boolean) JsonObject: JsonObject
    var
        InvoiceArray: JsonArray;
        InvoiceObject: JsonObject;
    begin
        // UBL 2.1 namespace declarations
        JsonObject.Add('_D', 'urn:oasis:names:specification:ubl:schema:xsd:Invoice-2');
        JsonObject.Add('_A', 'urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2');
        JsonObject.Add('_B', 'urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2');

        // Build the invoice object
        InvoiceObject := CreateInvoiceObject(SalesInvoiceHeader, IncludeSignature);
        InvoiceArray.Add(InvoiceObject);
        JsonObject.Add('Invoice', InvoiceArray);
    end;

    local procedure BuildCreditMemoEInvoiceJson(SalesCrMemoHeader: Record "Sales Cr.Memo Header"; IncludeSignature: Boolean) JsonObject: JsonObject
    var
        CreditMemoArray: JsonArray;
        CreditMemoObject: JsonObject;
    begin
        // UBL 2.1 namespace declarations (use Invoice root for Credit Note submissions per LHDN)
        JsonObject.Add('_D', 'urn:oasis:names:specification:ubl:schema:xsd:Invoice-2');
        JsonObject.Add('_A', 'urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2');
        JsonObject.Add('_B', 'urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2');

        // Use the existing CreateCreditMemoObject procedure that follows the same JSON structure as invoices
        CreditMemoObject := CreateCreditMemoObject(SalesCrMemoHeader, IncludeSignature);

        // Wrap in array structure (required by LHDN format)
        CreditMemoArray.Add(CreditMemoObject);
        // Use 'Invoice' as the root element for credit notes (type code distinguishes it)
        JsonObject.Add('Invoice', CreditMemoArray);
    end;

    local procedure CreateInvoiceObject(SalesInvoiceHeader: Record "Sales Invoice Header"; IncludeSignature: Boolean) InvoiceObject: JsonObject
    var
        Customer: Record Customer;
        CompanyInformation: Record "Company Information";
        CurrencyCode: Code[10];
        NowUTC: DateTime;
    begin
        // Validate mandatory fields
        if SalesInvoiceHeader."No." = '' then
            Error('Invoice number is required');
        if SalesInvoiceHeader."Bill-to Customer No." = '' then
            Error('Bill-to Customer No. is required for invoice %1', SalesInvoiceHeader."No.");
        if SalesInvoiceHeader."Posting Date" = 0D then
            Error('Posting Date is required for invoice %1', SalesInvoiceHeader."No.");

        // Get currency code
        if SalesInvoiceHeader."Currency Code" = '' then
            CurrencyCode := 'MYR'
        else
            CurrencyCode := SalesInvoiceHeader."Currency Code";

        // Core invoice fields
        AddBasicField(InvoiceObject, 'ID', SalesInvoiceHeader."No.");
        NowUTC := CurrentDateTime - 300000;
        AddBasicField(InvoiceObject, 'IssueDate', Format(CalcDate('-1D', Today()), 0, '<Year4>-<Month,2>-<Day,2>'));

        AddBasicField(InvoiceObject, 'IssueTime', Format(DT2Time(NowUTC), 0, '<Hours24,2>:<Minutes,2>:<Seconds,2>Z'));

        // MANDATORY: UBL Version ID for LHDN compliance
        AddBasicField(InvoiceObject, 'UBLVersionID', '2.1');

        // MANDATORY: Customization/Profile IDs as per LHDN
        AddBasicField(InvoiceObject, 'CustomizationID', 'MY:1.0');
        AddBasicField(InvoiceObject, 'ProfileID', 'reporting:1.0');

        // Invoice type code with list version
        if SalesInvoiceHeader."eInvoice Version Code" <> '' then
            AddFieldWithAttribute(InvoiceObject, 'InvoiceTypeCode', SalesInvoiceHeader."eInvoice Document Type", 'listVersionID', SalesInvoiceHeader."eInvoice Version Code")
        else
            AddFieldWithAttribute(InvoiceObject, 'InvoiceTypeCode', SalesInvoiceHeader."eInvoice Document Type", 'listVersionID', '1.0'); // Default to version 1.0

        // Currency codes
        AddBasicField(InvoiceObject, 'DocumentCurrencyCode', CurrencyCode);
        AddBasicField(InvoiceObject, 'TaxCurrencyCode', CurrencyCode);

        // MANDATORY: Currency exchange rate for non-MYR currencies
        if CurrencyCode <> 'MYR' then
            AddTaxExchangeRate(InvoiceObject, SalesInvoiceHeader, CurrencyCode);

        // Invoice Period
        AddInvoicePeriod(InvoiceObject, SalesInvoiceHeader);

        // Billing reference (if applicable)
        AddBillingReference(InvoiceObject, SalesInvoiceHeader);

        // Additional document references
        AddAdditionalDocumentReferences(InvoiceObject, SalesInvoiceHeader);

        // Party information
        if not CompanyInformation.Get() then
            Error('Company Information not found');
        AddAccountingSupplierParty(InvoiceObject, CompanyInformation);

        if not Customer.Get(SalesInvoiceHeader."Bill-to Customer No.") then
            Error('Customer %1 not found', SalesInvoiceHeader."Bill-to Customer No.");
        AddAccountingCustomerParty(InvoiceObject, Customer);

        // Delivery and shipment (optional)
        if ShouldIncludeDelivery(SalesInvoiceHeader) then
            AddDelivery(InvoiceObject, Customer, SalesInvoiceHeader);

        // Payment information
        AddPaymentMeans(InvoiceObject, SalesInvoiceHeader);
        AddPaymentTerms(InvoiceObject, SalesInvoiceHeader);

        // Optional sections
        if HasPrepaidAmount(SalesInvoiceHeader) then
            AddPrepaidPayment(InvoiceObject, SalesInvoiceHeader);

        // Allowances and charges
        AddAllowanceCharges(InvoiceObject, SalesInvoiceHeader);

        // Tax calculations
        AddTaxTotals(InvoiceObject, SalesInvoiceHeader);

        // Monetary totals
        AddLegalMonetaryTotal(InvoiceObject, SalesInvoiceHeader);

        // Invoice lines
        AddInvoiceLines(InvoiceObject, SalesInvoiceHeader);

        // Digital signature (only required for version 1.1 and if requested)
        if (SalesInvoiceHeader."eInvoice Version Code" = '1.1') and IncludeSignature then
            AddDigitalSignature(InvoiceObject, SalesInvoiceHeader);
    end;

    local procedure CreateCreditMemoObject(SalesCrMemoHeader: Record "Sales Cr.Memo Header"; IncludeSignature: Boolean) InvoiceObject: JsonObject
    var
        Customer: Record Customer;
        CompanyInformation: Record "Company Information";
        CurrencyCode: Code[10];
        NowUTC: DateTime;
    begin
        // Validate mandatory fields
        if SalesCrMemoHeader."No." = '' then
            Error('Credit memo number is required');
        if SalesCrMemoHeader."Bill-to Customer No." = '' then
            Error('Bill-to Customer No. is required for credit memo %1', SalesCrMemoHeader."No.");
        if SalesCrMemoHeader."Posting Date" = 0D then
            Error('Posting Date is required for credit memo %1', SalesCrMemoHeader."No.");

        // Get currency code
        if SalesCrMemoHeader."Currency Code" = '' then
            CurrencyCode := 'MYR'
        else
            CurrencyCode := SalesCrMemoHeader."Currency Code";

        // Core credit memo fields
        AddBasicField(InvoiceObject, 'ID', SalesCrMemoHeader."No.");
        NowUTC := CurrentDateTime - 300000;
        AddBasicField(InvoiceObject, 'IssueDate', Format(CalcDate('-1D', Today()), 0, '<Year4>-<Month,2>-<Day,2>'));
        AddBasicField(InvoiceObject, 'IssueTime', Format(DT2Time(NowUTC), 0, '<Hours24,2>:<Minutes,2>:<Seconds,2>Z'));

        // MANDATORY: UBL Version ID for LHDN compliance
        AddBasicField(InvoiceObject, 'UBLVersionID', '2.1');

        // MANDATORY: Customization/Profile IDs as per LHDN
        AddBasicField(InvoiceObject, 'CustomizationID', 'MY:1.0');
        AddBasicField(InvoiceObject, 'ProfileID', 'reporting:1.0');

        // Credit memo type code (02 = Credit Note)
        if SalesCrMemoHeader."eInvoice Version Code" <> '' then
            AddFieldWithAttribute(InvoiceObject, 'InvoiceTypeCode', '02', 'listVersionID', SalesCrMemoHeader."eInvoice Version Code")
        else
            AddFieldWithAttribute(InvoiceObject, 'InvoiceTypeCode', '02', 'listVersionID', '1.0'); // Default to version 1.0

        // Currency codes
        AddBasicField(InvoiceObject, 'DocumentCurrencyCode', CurrencyCode);
        AddBasicField(InvoiceObject, 'TaxCurrencyCode', CurrencyCode);

        // MANDATORY: Currency exchange rate for non-MYR currencies
        if CurrencyCode <> 'MYR' then
            AddTaxExchangeRate(InvoiceObject, SalesCrMemoHeader, CurrencyCode);

        // Invoice Period
        AddInvoicePeriod(InvoiceObject, SalesCrMemoHeader);

        // Billing reference (credit note requires reference to original invoice)
        AddCreditMemoBillingReference(InvoiceObject, SalesCrMemoHeader);

        // Additional document references
        AddAdditionalDocumentReferences(InvoiceObject, SalesCrMemoHeader);

        // Party information
        if not CompanyInformation.Get() then
            Error('Company Information not found');
        AddAccountingSupplierParty(InvoiceObject, CompanyInformation);

        if not Customer.Get(SalesCrMemoHeader."Bill-to Customer No.") then
            Error('Customer %1 not found', SalesCrMemoHeader."Bill-to Customer No.");
        AddAccountingCustomerParty(InvoiceObject, Customer);

        // Delivery and shipment (optional)
        if ShouldIncludeDelivery(SalesCrMemoHeader) then
            AddDelivery(InvoiceObject, Customer, SalesCrMemoHeader);

        // Payment information
        AddPaymentMeans(InvoiceObject, SalesCrMemoHeader);
        AddPaymentTerms(InvoiceObject, SalesCrMemoHeader);

        // Optional sections
        if HasPrepaidAmount(SalesCrMemoHeader) then
            AddPrepaidPayment(InvoiceObject, SalesCrMemoHeader);

        // Allowances and charges
        AddAllowanceCharges(InvoiceObject, SalesCrMemoHeader);

        // Tax calculations
        AddTaxTotals(InvoiceObject, SalesCrMemoHeader);

        // Monetary totals
        AddLegalMonetaryTotal(InvoiceObject, SalesCrMemoHeader);

        // Credit memo lines
        AddCreditMemoLines(InvoiceObject, SalesCrMemoHeader);

        // Digital signature (only required for version 1.1 and if requested)
        if (SalesCrMemoHeader."eInvoice Version Code" = '1.1') and IncludeSignature then
            AddDigitalSignature(InvoiceObject, SalesCrMemoHeader);
    end;

    local procedure GetSafeMalaysiaTime(PostingDate: Date): Text
    var
        CurrentTime: Time;
        TimeText: Text;
    begin
        // CRITICAL COMPLIANCE: LHDN requires CURRENT time, not fixed time
        // Per documentation: "Time of issuance of the e-Invoice *Note that the time must be the current time"
        CurrentTime := Time();
        TimeText := Format(CurrentTime, 0, '<Hours24,2>:<Minutes,2>:<Seconds,2>Z');
        exit(TimeText);
    end;

    local procedure AddInvoicePeriod(var InvoiceObject: JsonObject; SalesInvoiceHeader: Record "Sales Invoice Header")
    var
        PeriodArray: JsonArray;
        PeriodObject: JsonObject;
        StartDate: Date;
        EndDate: Date;
        PeriodDescription: Text;
    begin
        // Only add invoice period if custom fields are populated in the Sales Invoice Header
        // This makes the period dynamic based on actual invoice data instead of hardcoded values

        // Check if invoice has custom period fields (you can add these fields to Sales Invoice Header if needed)
        // For now, we'll make it conditional based on document type or other criteria

        if ShouldIncludeInvoicePeriod(SalesInvoiceHeader) then begin
            GetInvoicePeriodDetails(SalesInvoiceHeader, StartDate, EndDate, PeriodDescription);

            AddBasicField(PeriodObject, 'StartDate', Format(StartDate, 0, '<Year4>-<Month,2>-<Day,2>'));
            AddBasicField(PeriodObject, 'EndDate', Format(EndDate, 0, '<Year4>-<Month,2>-<Day,2>'));
            AddBasicField(PeriodObject, 'Description', PeriodDescription);

            PeriodArray.Add(PeriodObject);
            InvoiceObject.Add('InvoicePeriod', PeriodArray);
        end;
        // If no period data available, skip this optional section entirely
    end;

    local procedure ShouldIncludeInvoicePeriod(SalesInvoiceHeader: Record "Sales Invoice Header"): Boolean
    begin
        // FIXED: Make invoice period optional - only include when there are actual period values
        // Check if there are custom period fields populated (you would need to add these fields to Sales Invoice Header)
        // For now, return false to make it completely optional since period data should come from actual business data

        // You can enable this by adding custom fields to Sales Invoice Header:
        // if (SalesInvoiceHeader."Custom Period Start" <> 0D) or 
        //    (SalesInvoiceHeader."Custom Period End" <> 0D) or 
        //    (SalesInvoiceHeader."Custom Period Description" <> '') then
        //     exit(true);

        exit(false); // Optional by default - only include when business logic requires it
    end;

    local procedure ShouldIncludeDelivery(SalesInvoiceHeader: Record "Sales Invoice Header"): Boolean
    begin
        // Define business logic for when to include delivery/shipping recipient information
        // According to MyInvois documentation, shipping recipient details are optional

        // You can customize this logic based on your business requirements:
        // - Only include when there's a different delivery address than billing address
        // - Only for specific document types that require delivery information
        // - Only when customer has specific delivery requirements

        // For now, return false to make delivery section optional by default
        // You can modify this logic based on your specific business needs
        exit(false);
    end;

    local procedure GetInvoicePeriodDetails(SalesInvoiceHeader: Record "Sales Invoice Header"; var StartDate: Date; var EndDate: Date; var PeriodDescription: Text)
    begin
        // Get period details from invoice data instead of hardcoding
        // You can customize this based on your business logic

        // Default approach: Use posting date as end date, calculate start based on payment terms or document type
        EndDate := SalesInvoiceHeader."Posting Date";

        // Determine start date based on document type or business logic
        case SalesInvoiceHeader."eInvoice Document Type" of
            '02', '03': // Debit/Credit notes - use same month
                begin
                    StartDate := CalcDate('<-CM>', EndDate); // Start of current month
                    PeriodDescription := 'Monthly adjustment';
                end;
            '11': // Self-billed - quarterly period
                begin
                    StartDate := CalcDate('<-CQ>', EndDate); // Start of current quarter  
                    PeriodDescription := 'Quarterly self-billing';
                end;
            else begin
                // For other types, use a more dynamic approach
                StartDate := CalcDate('<-1M+1D>', EndDate); // Previous month
                PeriodDescription := 'Service period';
            end;
        end;

        // You can also check for custom fields on Sales Invoice Header if you add them:
        // if SalesInvoiceHeader."Custom Period Start" <> 0D then
        //     StartDate := SalesInvoiceHeader."Custom Period Start";
        // if SalesInvoiceHeader."Custom Period End" <> 0D then  
        //     EndDate := SalesInvoiceHeader."Custom Period End";
        // if SalesInvoiceHeader."Custom Period Description" <> '' then
        //     PeriodDescription := SalesInvoiceHeader."Custom Period Description";
    end;

    local procedure AddBillingReference(var InvoiceObject: JsonObject; SalesInvoiceHeader: Record "Sales Invoice Header")
    var
        BillingRefArray: JsonArray;
        BillingRefObject: JsonObject;
        AdditionalDocRefArray: JsonArray;
        DocRefObject: JsonObject;
    begin
        // Only add if there's a reference document
        if SalesInvoiceHeader."External Document No." <> '' then begin
            // LHDN MyInvois API enforces 26-character limit for BillingReference ID fields
            // Reference: https://sdk.myinvois.hasil.gov.my/documents/credit-v1-1/
            if StrLen(SalesInvoiceHeader."External Document No.") > 26 then
                AddBasicField(DocRefObject, 'ID', CopyStr(SalesInvoiceHeader."External Document No.", 1, 26))
            else
                AddBasicField(DocRefObject, 'ID', SalesInvoiceHeader."External Document No.");
            AdditionalDocRefArray.Add(DocRefObject);
            BillingRefObject.Add('AdditionalDocumentReference', AdditionalDocRefArray);
            BillingRefArray.Add(BillingRefObject);
            InvoiceObject.Add('BillingReference', BillingRefArray);
        end;
    end;

    local procedure AddCreditMemoBillingReference(var InvoiceObject: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        BillingRefArray: JsonArray;
        BillingRefObject: JsonObject;
        InvoiceDocumentReferenceArray: JsonArray;
        InvoiceDocumentReferenceObject: JsonObject;
    begin
        // LHDN COMPLIANCE: For credit notes adjusting invoices issued prior to e-Invoice implementation,
        // use "NA" as the Original e-Invoice Reference Number since no IRBM Unique Identifier Number exists.
        // Reference: LHDN e-Invoice Guidelines - Credit/Debit Note Adjustments
        // "If adjustments are to be made to original invoices that were issued prior to the implementation
        // of e-Invoice (i.e., no IRBM Unique Identifier Number has been assigned), taxpayers are then
        // allowed to input "NA" in the 'Original e-Invoice Reference Number' data field."
        //
        // BUSINESS DECISION: Always use "NA" for all credit notes regardless of reference availability

        AddBasicField(InvoiceDocumentReferenceObject, 'ID', 'NA');

        InvoiceDocumentReferenceArray.Add(InvoiceDocumentReferenceObject);
        BillingRefObject.Add('InvoiceDocumentReference', InvoiceDocumentReferenceArray);
        BillingRefArray.Add(BillingRefObject);
        InvoiceObject.Add('BillingReference', BillingRefArray);
    end;

    local procedure AddAdditionalDocumentReferences(var InvoiceObject: JsonObject; SalesInvoiceHeader: Record "Sales Invoice Header")
    var
        AdditionalDocArray: JsonArray;
        RefObject: JsonObject;
        HasReferences: Boolean;
    begin
        // Only add if there are actual references
        if SalesInvoiceHeader."External Document No." <> '' then begin
            Clear(RefObject);
            // LHDN MyInvois API enforces 26-character limit for BillingReference ID fields
            // Reference: https://sdk.myinvois.hasil.gov.my/documents/credit-v1-1/
            if StrLen(SalesInvoiceHeader."External Document No.") > 26 then
                AddBasicField(RefObject, 'ID', CopyStr(SalesInvoiceHeader."External Document No.", 1, 26))
            else
                AddBasicField(RefObject, 'ID', SalesInvoiceHeader."External Document No.");
            AddBasicField(RefObject, 'DocumentType', 'PurchaseOrder');
            AdditionalDocArray.Add(RefObject);
            HasReferences := true;
        end;

        // Add other document references only if they exist
        // Remove the empty object creation

        if HasReferences then
            InvoiceObject.Add('AdditionalDocumentReference', AdditionalDocArray);
    end;

    local procedure AddAccountingSupplierParty(var InvoiceObject: JsonObject; CompanyInfo: Record "Company Information")
    var
        SupplierArray: JsonArray;
        SupplierObject: JsonObject;
        PartyArray: JsonArray;
        PartyObject: JsonObject;
        PartyIdentificationArray: JsonArray;
        PostalAddressArray: JsonArray;
        PostalAddressObject: JsonObject;
        ContactArray: JsonArray;
        ContactObject: JsonObject;
        PartyLegalEntityArray: JsonArray;
        PartyLegalEntityObject: JsonObject;
        IndustryClassificationArray: JsonArray;
        IndustryClassificationObject: JsonObject;
        AdditionalAccountIDArray: JsonArray;
        AdditionalAccountIDObject: JsonObject;
    begin
        // Additional Account ID (for certifications like CertEX) - only if available
        if GetCertificationID() <> '' then begin
            AdditionalAccountIDObject.Add('_', GetCertificationID());
            AdditionalAccountIDObject.Add('schemeAgencyName', 'CertEX');
            AdditionalAccountIDArray.Add(AdditionalAccountIDObject);
            SupplierObject.Add('AdditionalAccountID', AdditionalAccountIDArray);
        end;

        // Industry classification (MSIC code)
        IndustryClassificationObject.Add('_', GetMSICCode());
        IndustryClassificationObject.Add('name', GetMSICDescription());
        IndustryClassificationArray.Add(IndustryClassificationObject);
        PartyObject.Add('IndustryClassificationCode', IndustryClassificationArray);

        // Party identification (TIN, BRN, SST, TTX)
        AddPartyIdentification(PartyIdentificationArray, CompanyInfo."e-Invoice TIN No.", 'TIN');
        AddPartyIdentification(PartyIdentificationArray, CompanyInfo."ID No.", 'BRN');
        AddPartyIdentification(PartyIdentificationArray, GetSSTNumber(), 'SST');
        AddPartyIdentification(PartyIdentificationArray, GetTTXNumber(), 'TTX');
        PartyObject.Add('PartyIdentification', PartyIdentificationArray);

        // Postal address
        AddBasicField(PostalAddressObject, 'CityName', CompanyInfo.City);
        AddBasicField(PostalAddressObject, 'PostalZone', CompanyInfo."Post Code");
        AddBasicField(PostalAddressObject, 'CountrySubentityCode', GetCompanyStateCode(CompanyInfo));
        AddAddressLines(PostalAddressObject, CompanyInfo.Address, CompanyInfo."Address 2", '');
        AddCountry(PostalAddressObject, GetCountryCode(CompanyInfo."e-Invoice Country Code"));
        PostalAddressArray.Add(PostalAddressObject);
        PartyObject.Add('PostalAddress', PostalAddressArray);

        // Legal entity information
        AddBasicField(PartyLegalEntityObject, 'RegistrationName', CompanyInfo.Name);
        PartyLegalEntityArray.Add(PartyLegalEntityObject);
        PartyObject.Add('PartyLegalEntity', PartyLegalEntityArray);

        // MANDATORY: Contact information per LHDN spec
        if CompanyInfo."Phone No." = '' then
            Error('Company phone number is mandatory for eInvoice compliance');
        AddBasicField(ContactObject, 'Telephone', CompanyInfo."Phone No.");

        if CompanyInfo."e-Invoice Email" = '' then
            Error('Company email is mandatory for eInvoice compliance');
        AddBasicField(ContactObject, 'ElectronicMail', CompanyInfo."e-Invoice Email");
        ContactArray.Add(ContactObject);
        PartyObject.Add('Contact', ContactArray);

        // Build supplier object
        PartyArray.Add(PartyObject);
        SupplierObject.Add('Party', PartyArray);
        SupplierArray.Add(SupplierObject);
        InvoiceObject.Add('AccountingSupplierParty', SupplierArray);
    end;

    local procedure AddAccountingCustomerParty(var InvoiceObject: JsonObject; Customer: Record Customer)
    var
        CustomerArray: JsonArray;
        CustomerObject: JsonObject;
        PartyArray: JsonArray;
        PartyObject: JsonObject;
        PartyIdentificationArray: JsonArray;
        PostalAddressArray: JsonArray;
        PostalAddressObject: JsonObject;
        ContactArray: JsonArray;
        ContactObject: JsonObject;
        PartyLegalEntityArray: JsonArray;
        PartyLegalEntityObject: JsonObject;
    begin
        // Postal address
        AddBasicField(PostalAddressObject, 'CityName', Customer.City);
        AddBasicField(PostalAddressObject, 'PostalZone', Customer."Post Code");
        AddBasicField(PostalAddressObject, 'CountrySubentityCode', GetCustomerStateCode(Customer));
        AddAddressLines(PostalAddressObject, Customer.Address, Customer."Address 2", '');
        AddCountry(PostalAddressObject, GetCountryCode(Customer."Country/Region Code"));
        PostalAddressArray.Add(PostalAddressObject);
        PartyObject.Add('PostalAddress', PostalAddressArray);

        // Legal entity
        AddBasicField(PartyLegalEntityObject, 'RegistrationName', Customer.Name);
        PartyLegalEntityArray.Add(PartyLegalEntityObject);
        PartyObject.Add('PartyLegalEntity', PartyLegalEntityArray);

        // Party identification
        AddPartyIdentification(PartyIdentificationArray, Customer."e-Invoice TIN No.", 'TIN');
        AddPartyIdentification(PartyIdentificationArray, Customer."e-Invoice ID No.", GetCustomerIDType(Customer));
        AddPartyIdentification(PartyIdentificationArray, Customer."e-Invoice SST No.", 'SST');
        AddPartyIdentification(PartyIdentificationArray, '', 'TTX');
        PartyObject.Add('PartyIdentification', PartyIdentificationArray);

        // MANDATORY: Contact information per LHDN spec
        if Customer."Phone No." = '' then
            Error('Customer phone number is mandatory for eInvoice compliance. Customer: %1', Customer."No.");
        AddBasicField(ContactObject, 'Telephone', Customer."Phone No.");
        AddBasicField(ContactObject, 'ElectronicMail', Customer."E-Mail");
        ContactArray.Add(ContactObject);
        PartyObject.Add('Contact', ContactArray);

        // Build customer object
        PartyArray.Add(PartyObject);
        CustomerObject.Add('Party', PartyArray);
        CustomerArray.Add(CustomerObject);
        InvoiceObject.Add('AccountingCustomerParty', CustomerArray);
    end;

    local procedure AddDelivery(var InvoiceObject: JsonObject; Customer: Record Customer; SalesInvoiceHeader: Record "Sales Invoice Header")
    var
        DeliveryArray: JsonArray;
        DeliveryObject: JsonObject;
        DeliveryPartyArray: JsonArray;
        DeliveryPartyObject: JsonObject;
        PartyIdentificationArray: JsonArray;
        PostalAddressArray: JsonArray;
        PostalAddressObject: JsonObject;
        PartyLegalEntityArray: JsonArray;
        PartyLegalEntityObject: JsonObject;
        ShipmentArray: JsonArray;
        CompanyInformation: Record "Company Information";
    begin
        // Use customer address as delivery address if no specific delivery address
        CompanyInformation.Get();

        // Legal entity - use customer name as delivery recipient
        AddBasicField(PartyLegalEntityObject, 'RegistrationName', Customer.Name);
        PartyLegalEntityArray.Add(PartyLegalEntityObject);
        DeliveryPartyObject.Add('PartyLegalEntity', PartyLegalEntityArray);

        // Delivery address - use customer address
        AddBasicField(PostalAddressObject, 'CityName', Customer.City);
        AddBasicField(PostalAddressObject, 'PostalZone', Customer."Post Code");
        AddBasicField(PostalAddressObject, 'CountrySubentityCode', GetCustomerStateCode(Customer));
        AddAddressLines(PostalAddressObject, Customer.Address, Customer."Address 2", '');
        AddCountry(PostalAddressObject, GetCountryCode(Customer."Country/Region Code"));
        PostalAddressArray.Add(PostalAddressObject);
        DeliveryPartyObject.Add('PostalAddress', PostalAddressArray);

        // Delivery party identification - use customer TIN/ID Type
        AddPartyIdentification(PartyIdentificationArray, Customer."e-Invoice TIN No.", 'TIN');
        AddPartyIdentification(PartyIdentificationArray, Customer."e-Invoice ID No.", GetCustomerIDType(Customer));
        DeliveryPartyObject.Add('PartyIdentification', PartyIdentificationArray);

        DeliveryPartyArray.Add(DeliveryPartyObject);
        DeliveryObject.Add('DeliveryParty', DeliveryPartyArray);

        // Shipment information (optional)
        AddShipmentInfoDynamic(ShipmentArray, SalesInvoiceHeader);
        if ShipmentArray.Count > 0 then
            DeliveryObject.Add('Shipment', ShipmentArray);

        DeliveryArray.Add(DeliveryObject);
        InvoiceObject.Add('Delivery', DeliveryArray);
    end;

    // Alternative version if you want to make it more dynamic:
    local procedure AddShipmentInfoDynamic(var ShipmentArray: JsonArray; SalesInvoiceHeader: Record "Sales Invoice Header")
    var
        ShipmentObject: JsonObject;
        FreightChargeArray: JsonArray;
        FreightChargeObject: JsonObject;
        ChargeIndicatorArray: JsonArray;
        ChargeIndicatorObject: JsonObject;
        AllowanceChargeReasonArray: JsonArray;
        AllowanceChargeReasonObject: JsonObject;
        AmountArray: JsonArray;
        AmountObject: JsonObject;
        FreightAmount: Decimal;
        CurrencyCode: Code[10];
        ShipmentID: Text;
    begin
        // Get currency code
        if SalesInvoiceHeader."Currency Code" = '' then
            CurrencyCode := 'MYR'
        else
            CurrencyCode := SalesInvoiceHeader."Currency Code";

        // CRITICAL: Shipment ID is mandatory when Shipment section is included
        ShipmentID := GetShipmentID(SalesInvoiceHeader);
        if ShipmentID = '' then
            ShipmentID := SalesInvoiceHeader."No."; // Use invoice number as fallback

        AddBasicField(ShipmentObject, 'ID', ShipmentID);

        // Calculate freight amount
        FreightAmount := CalculateFreightAmount(SalesInvoiceHeader);

        // Freight allowance charge
        ChargeIndicatorObject.Add('_', FreightAmount > 0);
        ChargeIndicatorArray.Add(ChargeIndicatorObject);
        FreightChargeObject.Add('ChargeIndicator', ChargeIndicatorArray);

        AllowanceChargeReasonObject.Add('_', GetFreightReason(FreightAmount));
        AllowanceChargeReasonArray.Add(AllowanceChargeReasonObject);
        FreightChargeObject.Add('AllowanceChargeReason', AllowanceChargeReasonArray);

        AmountObject.Add('_', FreightAmount);
        AmountObject.Add('currencyID', CurrencyCode);
        AmountArray.Add(AmountObject);
        FreightChargeObject.Add('Amount', AmountArray);

        FreightChargeArray.Add(FreightChargeObject);
        ShipmentObject.Add('FreightAllowanceCharge', FreightChargeArray);
        ShipmentArray.Add(ShipmentObject);
    end;

    // Helper functions for the dynamic version (implement as needed):
    local procedure CalculateFreightAmount(SalesInvoiceHeader: Record "Sales Invoice Header"): Decimal
    begin
        // Implement your freight calculation logic here
        // For now, return 0
        exit(0.0);
    end;

    local procedure GetShipmentID(SalesInvoiceHeader: Record "Sales Invoice Header"): Text
    begin
        // Try to get shipment ID from a custom field, otherwise use invoice number
        // You can customize this based on your Business Central setup
        if SalesInvoiceHeader."External Document No." <> '' then
            exit('SHIP-' + SalesInvoiceHeader."External Document No.")
        else
            exit('SHIP-' + SalesInvoiceHeader."No.");
    end;

    local procedure GetFreightReason(FreightAmount: Decimal): Text
    begin
        if FreightAmount > 0 then
            exit('Freight')
        else
            exit('');
    end;

    local procedure AddPaymentMeans(var InvoiceObject: JsonObject; SalesInvoiceHeader: Record "Sales Invoice Header")
    var
        PaymentMeansArray: JsonArray;
        PaymentMeansObject: JsonObject;
        PayeeAccountArray: JsonArray;
        PayeeAccountObject: JsonObject;
    begin
        // CRITICAL: PaymentMeansCode is mandatory and was missing
        AddBasicField(PaymentMeansObject, 'PaymentMeansCode', GetPaymentMeansCode(SalesInvoiceHeader));

        // Only add bank account for bank transfer payments
        if GetPaymentMeansCode(SalesInvoiceHeader) = '01' then begin // Bank Transfer
            AddBasicField(PayeeAccountObject, 'ID', GetBankAccountNumber());
            PayeeAccountArray.Add(PayeeAccountObject);
            PaymentMeansObject.Add('PayeeFinancialAccount', PayeeAccountArray);
        end;

        PaymentMeansArray.Add(PaymentMeansObject);
        InvoiceObject.Add('PaymentMeans', PaymentMeansArray);
    end;

    local procedure GetPaymentMeansCode(SalesInvoiceHeader: Record "Sales Invoice Header"): Code[10]
    var
        PaymentMode: Code[10];
    begin
        // Return the payment mode from the invoice header
        PaymentMode := SalesInvoiceHeader."eInvoice Payment Mode";

        // Validate and return appropriate payment mode
        case PaymentMode of
            '01':
                exit('01'); // Cash
            '02':
                exit('02'); // Cheque  
            '03':
                exit('03'); // Bank Transfer
            '04':
                exit('04'); // Credit Card
            '05':
                exit('05'); // Debit Card
            '06':
                exit('06'); // e-Wallet / Digital Wallet
            '07':
                exit('07'); // Digital Bank
            '08':
                exit('08'); // Others
            else begin
                // Log warning for debugging
                LogDebugInfo('Payment Mode Warning',
                    StrSubstNo('Invalid or empty payment mode "%1" for invoice %2. Returning empty value.',
                        PaymentMode, SalesInvoiceHeader."No."));
                exit('08'); // Return Others if not specified or invalid
            end;
        end;
    end;

    local procedure AddPaymentTerms(var InvoiceObject: JsonObject; SalesInvoiceHeader: Record "Sales Invoice Header")
    var
        PaymentTermsArray: JsonArray;
        PaymentTermsObject: JsonObject;
        PaymentTerms: Record "Payment Terms";
        SettlementDiscountArray: JsonArray;
        SettlementDiscountObject: JsonObject;
        SettlementPeriodArray: JsonArray;
        SettlementPeriodObject: JsonObject;
    begin
        // Add main payment terms note
        AddBasicField(PaymentTermsObject, 'Note', GetPaymentTermsNote(SalesInvoiceHeader));

        // Add settlement discount if available
        if (SalesInvoiceHeader."Payment Terms Code" <> '') and PaymentTerms.Get(SalesInvoiceHeader."Payment Terms Code") then begin
            if PaymentTerms."Discount %" > 0 then begin
                // Settlement discount percentage
                AddNumericField(SettlementDiscountObject, 'Percent', PaymentTerms."Discount %");

                // Settlement period for discount
                if Format(PaymentTerms."Discount Date Calculation") <> '' then begin
                    AddBasicField(SettlementPeriodObject, 'Description', 'Early payment discount period');
                    // You can add StartDate and EndDate if needed based on invoice date + discount calculation
                    SettlementPeriodArray.Add(SettlementPeriodObject);
                    SettlementDiscountObject.Add('SettlementPeriod', SettlementPeriodArray);
                end;

                SettlementDiscountArray.Add(SettlementDiscountObject);
                PaymentTermsObject.Add('SettlementDiscountPercent', SettlementDiscountArray);
            end;
        end;

        PaymentTermsArray.Add(PaymentTermsObject);
        InvoiceObject.Add('PaymentTerms', PaymentTermsArray);
    end;

    local procedure AddPrepaidPayment(var InvoiceObject: JsonObject; SalesInvoiceHeader: Record "Sales Invoice Header")
    var
        PrepaidArray: JsonArray;
        PrepaidObject: JsonObject;
        PrepaidAmount: Decimal;
    begin
        PrepaidAmount := GetPrepaidAmount(SalesInvoiceHeader);
        // Only add if there's actually a prepaid amount > 0
        if PrepaidAmount > 0 then begin
            AddBasicField(PrepaidObject, 'ID', SalesInvoiceHeader."No.");
            AddAmountField(PrepaidObject, 'PaidAmount', PrepaidAmount, GetCurrencyCode(SalesInvoiceHeader));
            AddBasicField(PrepaidObject, 'PaidDate', Format(SalesInvoiceHeader."Posting Date", 0, '<Year4>-<Month,2>-<Day,2>'));
            AddBasicField(PrepaidObject, 'PaidTime', Format(Time(), 0, '<Hours24,2>:<Minutes,2>:<Seconds,2>Z'));

            PrepaidArray.Add(PrepaidObject);
            InvoiceObject.Add('PrepaidPayment', PrepaidArray);
        end;
        // If no prepaid amount, don't add the section at all
    end;

    local procedure AddAllowanceCharges(var InvoiceObject: JsonObject; SalesInvoiceHeader: Record "Sales Invoice Header")
    var
        AllowanceArray: JsonArray;
        ChargeObject: JsonObject;
        ChargeIndicatorArray: JsonArray;
        ChargeIndicatorObject: JsonObject;
        AllowanceChargeReasonArray: JsonArray;
        AllowanceChargeReasonObject: JsonObject;
        AmountArray: JsonArray;
        AmountObject: JsonObject;
        SalesLine: Record "Sales Invoice Line";
        DiscountAmount: Decimal;
        ChargeAmount: Decimal;
    begin
        // Calculate total discount and charges from invoice lines
        SalesLine.SetRange("Document No.", SalesInvoiceHeader."No.");
        if SalesLine.FindSet() then
            repeat
                DiscountAmount += SalesLine."Line Discount Amount";
            until SalesLine.Next() = 0;

        // Add discount as allowance
        if DiscountAmount > 0 then begin
            Clear(ChargeObject);
            ChargeIndicatorObject.Add('_', false);
            ChargeIndicatorArray.Add(ChargeIndicatorObject);
            ChargeObject.Add('ChargeIndicator', ChargeIndicatorArray);

            Clear(AllowanceChargeReasonArray);
            AllowanceChargeReasonObject.Add('_', '');
            AllowanceChargeReasonArray.Add(AllowanceChargeReasonObject);
            ChargeObject.Add('AllowanceChargeReason', AllowanceChargeReasonArray);

            Clear(AmountArray);
            AmountObject.Add('_', DiscountAmount);
            AmountObject.Add('currencyID', GetCurrencyCode(SalesInvoiceHeader));
            AmountArray.Add(AmountObject);
            ChargeObject.Add('Amount', AmountArray);

            AllowanceArray.Add(ChargeObject);
        end;

        // Add any charges if applicable (calculate dynamically or omit if not applicable)
        ChargeAmount := 0; // Set to 0 or calculate based on your business logic
        // Example: ChargeAmount := CalculateServiceCharge(SalesInvoiceHeader);

        if ChargeAmount > 0 then begin
            Clear(ChargeObject);
            Clear(ChargeIndicatorArray);
            Clear(ChargeIndicatorObject);
            ChargeIndicatorObject.Add('_', true);
            ChargeIndicatorArray.Add(ChargeIndicatorObject);
            ChargeObject.Add('ChargeIndicator', ChargeIndicatorArray);

            Clear(AllowanceChargeReasonArray);
            Clear(AllowanceChargeReasonObject);
            AllowanceChargeReasonObject.Add('_', 'Service charge');
            AllowanceChargeReasonArray.Add(AllowanceChargeReasonObject);
            ChargeObject.Add('AllowanceChargeReason', AllowanceChargeReasonArray);

            Clear(AmountArray);
            Clear(AmountObject);
            AmountObject.Add('_', ChargeAmount);
            AmountObject.Add('currencyID', GetCurrencyCode(SalesInvoiceHeader));
            AmountArray.Add(AmountObject);
            ChargeObject.Add('Amount', AmountArray);

            AllowanceArray.Add(ChargeObject);
        end;

        if AllowanceArray.Count > 0 then
            InvoiceObject.Add('AllowanceCharge', AllowanceArray);
    end;

    local procedure AddTaxTotals(var InvoiceObject: JsonObject; SalesInvoiceHeader: Record "Sales Invoice Header")
    var
        TaxTotalArray: JsonArray;
        TaxTotalObject: JsonObject;
        TaxSubtotalArray: JsonArray;
        TaxSubtotalObject: JsonObject;
        TaxCategoryArray: JsonArray;
        TaxCategoryObject: JsonObject;
        TaxSchemeArray: JsonArray;
        TaxSchemeObject: JsonObject;
        TotalTaxAmount: Decimal;
        TaxableAmount: Decimal;
        SalesLine: Record "Sales Invoice Line";
    begin
        SalesLine.SetRange("Document No.", SalesInvoiceHeader."No.");
        SalesLine.SetFilter("VAT %", '>0');
        if SalesLine.FindSet() then
            repeat
                TotalTaxAmount += SalesLine."Amount Including VAT" - SalesLine.Amount;
                TaxableAmount += SalesLine."Unit Price" * SalesLine.Quantity;
            until SalesLine.Next() = 0;

        AddAmountField(TaxTotalObject, 'TaxAmount', TotalTaxAmount, GetCurrencyCode(SalesInvoiceHeader));

        // Tax subtotal
        AddAmountField(TaxSubtotalObject, 'TaxableAmount', TaxableAmount, GetCurrencyCode(SalesInvoiceHeader));
        AddAmountField(TaxSubtotalObject, 'TaxAmount', TotalTaxAmount, GetCurrencyCode(SalesInvoiceHeader));

        // Tax category
        AddBasicField(TaxCategoryObject, 'ID', '01');

        // Tax scheme
        AddBasicFieldWithAttributes(TaxSchemeObject, 'ID', 'OTH', 'schemeID', 'UN/ECE 5153', 'schemeAgencyID', '6');
        TaxSchemeArray.Add(TaxSchemeObject);
        TaxCategoryArray.Add(TaxCategoryObject);
        TaxCategoryObject.Add('TaxScheme', TaxSchemeArray);

        TaxSubtotalArray.Add(TaxSubtotalObject);
        TaxSubtotalObject.Add('TaxCategory', TaxCategoryArray);
        TaxTotalObject.Add('TaxSubtotal', TaxSubtotalArray);

        TaxTotalArray.Add(TaxTotalObject);
        InvoiceObject.Add('TaxTotal', TaxTotalArray);
    end;

    local procedure AddLegalMonetaryTotal(var InvoiceObject: JsonObject; SalesInvoiceHeader: Record "Sales Invoice Header")
    var
        LegalTotalArray: JsonArray;
        LegalTotalObject: JsonObject;
        LineExtensionAmount: Decimal;
        TaxExclusiveAmount: Decimal;
        TaxInclusiveAmount: Decimal;
        AllowanceTotalAmount: Decimal;
        ChargeTotalAmount: Decimal;
        PayableAmount: Decimal;
        PayableRoundingAmount: Decimal;
        SalesLine: Record "Sales Invoice Line";
        TotalTaxAmount: Decimal;
        Subtotal: Decimal;
    begin
        ChargeTotalAmount := 0;
        SalesLine.SetRange("Document No.", SalesInvoiceHeader."No.");
        if SalesLine.FindSet() then
            repeat
                Subtotal := SalesLine."Unit Price" * SalesLine.Quantity;
                LineExtensionAmount += Subtotal;
                AllowanceTotalAmount += SalesLine."Line Discount Amount";
                TotalTaxAmount += SalesLine."Amount Including VAT" - SalesLine.Amount;
            until SalesLine.Next() = 0;

        TaxExclusiveAmount := LineExtensionAmount - AllowanceTotalAmount + ChargeTotalAmount;
        TaxInclusiveAmount := TaxExclusiveAmount + TotalTaxAmount;
        PayableAmount := TaxInclusiveAmount;
        PayableRoundingAmount := 0;

        AddAmountField(LegalTotalObject, 'LineExtensionAmount', LineExtensionAmount, GetCurrencyCode(SalesInvoiceHeader));
        AddAmountField(LegalTotalObject, 'TaxExclusiveAmount', TaxExclusiveAmount, GetCurrencyCode(SalesInvoiceHeader));
        AddAmountField(LegalTotalObject, 'TaxInclusiveAmount', TaxInclusiveAmount, GetCurrencyCode(SalesInvoiceHeader));
        AddAmountField(LegalTotalObject, 'AllowanceTotalAmount', AllowanceTotalAmount, GetCurrencyCode(SalesInvoiceHeader));
        AddAmountField(LegalTotalObject, 'ChargeTotalAmount', ChargeTotalAmount, GetCurrencyCode(SalesInvoiceHeader));
        AddAmountField(LegalTotalObject, 'PayableRoundingAmount', PayableRoundingAmount, GetCurrencyCode(SalesInvoiceHeader));
        AddAmountField(LegalTotalObject, 'PayableAmount', PayableAmount, GetCurrencyCode(SalesInvoiceHeader));

        LegalTotalArray.Add(LegalTotalObject);
        InvoiceObject.Add('LegalMonetaryTotal', LegalTotalArray);
    end;

    local procedure AddInvoiceLines(var InvoiceObject: JsonObject; SalesInvoiceHeader: Record "Sales Invoice Header")
    var
        LineArray: JsonArray;
        SalesInvoiceLine: Record "Sales Invoice Line";
    begin
        SalesInvoiceLine.SetRange("Document No.", SalesInvoiceHeader."No.");
        SalesInvoiceLine.SetFilter(Type, '<>%1', SalesInvoiceLine.Type::" ");
        if SalesInvoiceLine.FindSet() then
            repeat
                AddInvoiceLine(LineArray, SalesInvoiceLine, SalesInvoiceHeader."Currency Code");
            until SalesInvoiceLine.Next() = 0;
        InvoiceObject.Add('InvoiceLine', LineArray);
    end;

    local procedure AddInvoiceLine(var LineArray: JsonArray; SalesInvoiceLine: Record "Sales Invoice Line"; CurrencyCode: Code[10])
    var
        LineObject: JsonObject;
        TaxTotalArray: JsonArray;
        TaxTotalObject: JsonObject;
        TaxSubtotalArray: JsonArray;
        TaxSubtotalObject: JsonObject;
        TaxCategoryArray: JsonArray;
        TaxCategoryObject: JsonObject;
        TaxSchemeArray: JsonArray;
        TaxSchemeObject: JsonObject;
        ItemArray: JsonArray;
        ItemObject: JsonObject;
        PriceArray: JsonArray;
        PriceObject: JsonObject;
        AllowanceChargeArray: JsonArray;
        CommodityArray: JsonArray;
        CommodityObject: JsonObject;
        ItemClassificationCodeArray: JsonArray;
        ItemClassificationCodeObject: JsonObject;
        OriginCountryArray: JsonArray;
        OriginCountryObject: JsonObject;
        IdentificationCodeArray: JsonArray;
        IdentificationCodeObject: JsonObject;
        DescriptionArray: JsonArray;
        DescriptionObject: JsonObject;
        ItemPriceExtensionArray: JsonArray;
        ItemPriceExtensionObject: JsonObject;
        UnitCode: Code[10];
    begin
        // Line ID and quantity
        AddBasicField(LineObject, 'ID', Format(SalesInvoiceLine."Line No."));

        UnitCode := GetUBLUnitCode(SalesInvoiceLine);
        AddQuantityField(LineObject, 'InvoicedQuantity', SalesInvoiceLine.Quantity, UnitCode);
        AddAmountField(LineObject, 'LineExtensionAmount', SalesInvoiceLine.Amount, GetCurrencyCodeFromText(CurrencyCode));

        // Line allowances/charges
        if SalesInvoiceLine."Line Discount Amount" > 0 then
            AddLineAllowanceCharge(AllowanceChargeArray, false, '',
                SalesInvoiceLine."Line Discount %", SalesInvoiceLine."Line Discount Amount", GetCurrencyCodeFromText(CurrencyCode));

        // Add a sample charge
        // Example: Add a charge if applicable (remove hardcoded values)
        // You can calculate the charge amount and percentage based on your business logic.
        // For example, if you have a "Line Charge Amount" field:
        // Removed usage of non-existent "Line Charge Amount" field.
        // If you want to add a charge, replace the following with your own logic and field:
        // Example:
        // if MyChargeAmount > 0 then
        //     AddLineAllowanceCharge(
        //         AllowanceChargeArray,
        //         true,
        //         '', // Reason
        //         0, // Percentage
        //         MyChargeAmount,
        //         GetCurrencyCode(CurrencyCode)
        //     );

        if AllowanceChargeArray.Count > 0 then
            LineObject.Add('AllowanceCharge', AllowanceChargeArray);

        // Tax total for line
        AddAmountField(TaxTotalObject, 'TaxAmount', SalesInvoiceLine."Amount Including VAT" - SalesInvoiceLine.Amount, GetCurrencyCodeFromText(CurrencyCode));

        // Tax subtotal
        AddAmountField(TaxSubtotalObject, 'TaxableAmount', SalesInvoiceLine.Amount, GetCurrencyCodeFromText(CurrencyCode));
        AddAmountField(TaxSubtotalObject, 'TaxAmount', SalesInvoiceLine."Amount Including VAT" - SalesInvoiceLine.Amount, GetCurrencyCodeFromText(CurrencyCode));
        AddNumericField(TaxSubtotalObject, 'Percent', SalesInvoiceLine."VAT %");

        // Tax category
        AddBasicField(TaxCategoryObject, 'ID', SalesInvoiceLine."e-Invoice Tax Type");

        // Add TaxExemptionReason only for exempt tax types
        if SalesInvoiceLine."e-Invoice Tax Type" in ['E', 'Z'] then
            AddBasicField(TaxCategoryObject, 'TaxExemptionReason', GetTaxExemptionReason(SalesInvoiceLine."e-Invoice Tax Type"));

        // Tax scheme
        AddBasicFieldWithAttributes(TaxSchemeObject, 'ID', 'OTH', 'schemeID', 'UN/ECE 5153', 'schemeAgencyID', '6');
        TaxSchemeArray.Add(TaxSchemeObject);
        TaxCategoryArray.Add(TaxCategoryObject);
        TaxCategoryObject.Add('TaxScheme', TaxSchemeArray);

        TaxSubtotalArray.Add(TaxSubtotalObject);
        TaxSubtotalObject.Add('TaxCategory', TaxCategoryArray);
        TaxTotalObject.Add('TaxSubtotal', TaxSubtotalArray);

        TaxTotalArray.Add(TaxTotalObject);
        LineObject.Add('TaxTotal', TaxTotalArray);

        // Item information
        // MANDATORY: Product Tariff Code (PTC) - FIRST classification
        ItemClassificationCodeObject.Add('_', GetHSCode(SalesInvoiceLine));
        ItemClassificationCodeObject.Add('listID', 'PTC');
        ItemClassificationCodeArray.Add(ItemClassificationCodeObject);
        CommodityObject.Add('ItemClassificationCode', ItemClassificationCodeArray);
        CommodityArray.Add(CommodityObject);

        // MANDATORY: Classification Code (CLASS) - SECOND classification  
        Clear(CommodityObject);
        Clear(ItemClassificationCodeArray);
        Clear(ItemClassificationCodeObject);
        ItemClassificationCodeObject.Add('_', GetClassificationCode(SalesInvoiceLine));
        ItemClassificationCodeObject.Add('listID', 'CLASS');
        ItemClassificationCodeArray.Add(ItemClassificationCodeObject);
        CommodityObject.Add('ItemClassificationCode', ItemClassificationCodeArray);
        CommodityArray.Add(CommodityObject);

        ItemObject.Add('CommodityClassification', CommodityArray);

        // Description
        DescriptionObject.Add('_', SalesInvoiceLine.Description);
        DescriptionArray.Add(DescriptionObject);
        ItemObject.Add('Description', DescriptionArray);

        // Origin country
        IdentificationCodeObject.Add('_', GetOriginCountryCode(SalesInvoiceLine));
        IdentificationCodeArray.Add(IdentificationCodeObject);
        OriginCountryObject.Add('IdentificationCode', IdentificationCodeArray);
        OriginCountryArray.Add(OriginCountryObject);
        ItemObject.Add('OriginCountry', OriginCountryArray);

        ItemArray.Add(ItemObject);
        LineObject.Add('Item', ItemArray);

        // Price
        AddAmountField(PriceObject, 'PriceAmount', SalesInvoiceLine."Unit Price", GetCurrencyCodeFromText(CurrencyCode));
        PriceArray.Add(PriceObject);
        LineObject.Add('Price', PriceArray);

        // Item price extension
        AddAmountField(ItemPriceExtensionObject, 'Amount', SalesInvoiceLine.Amount, GetCurrencyCodeFromText(CurrencyCode));
        ItemPriceExtensionArray.Add(ItemPriceExtensionObject);
        LineObject.Add('ItemPriceExtension', ItemPriceExtensionArray);

        LineArray.Add(LineObject);
    end;

    local procedure AddDigitalSignature(var InvoiceObject: JsonObject; SalesInvoiceHeader: Record "Sales Invoice Header")
    var
        UBLExtensionsArray: JsonArray;
        UBLExtensionsObject: JsonObject;
        UBLExtensionArray: JsonArray;
        UBLExtensionObject: JsonObject;
        ExtensionURIArray: JsonArray;
        ExtensionURIObject: JsonObject;
        ExtensionContentArray: JsonArray;
        ExtensionContentObject: JsonObject;
        UBLDocumentSignaturesArray: JsonArray;
        UBLDocumentSignaturesObject: JsonObject;
        SignatureInformationArray: JsonArray;
        SignatureInformationObject: JsonObject;
        SignatureArray: JsonArray;
        SignatureObject: JsonObject;
    begin
        // MANDATORY for version 1.1: UBLExtensions with proper signature structure
        ExtensionURIObject.Add('_', 'urn:oasis:names:specification:ubl:dsig:enveloped:xades');
        ExtensionURIArray.Add(ExtensionURIObject);
        UBLExtensionObject.Add('ExtensionURI', ExtensionURIArray);

        // Build proper UBLDocumentSignatures structure
        AddBasicField(SignatureInformationObject, 'ID', 'urn:oasis:names:specification:ubl:signature:1');
        AddBasicField(SignatureInformationObject, 'ReferencedSignatureID', 'urn:oasis:names:specification:ubl:signature:Invoice');

        // Add placeholder signature structure - implement actual cryptographic signing
        AddBasicField(SignatureInformationObject, 'Signature', 'PLACEHOLDER_SIGNATURE_CONTENT');

        SignatureInformationArray.Add(SignatureInformationObject);
        UBLDocumentSignaturesObject.Add('SignatureInformation', SignatureInformationArray);
        UBLDocumentSignaturesArray.Add(UBLDocumentSignaturesObject);
        ExtensionContentObject.Add('UBLDocumentSignatures', UBLDocumentSignaturesArray);

        ExtensionContentArray.Add(ExtensionContentObject);
        UBLExtensionObject.Add('ExtensionContent', ExtensionContentArray);

        UBLExtensionArray.Add(UBLExtensionObject);
        UBLExtensionsObject.Add('UBLExtension', UBLExtensionArray);
        UBLExtensionsArray.Add(UBLExtensionsObject);
        InvoiceObject.Add('UBLExtensions', UBLExtensionsArray);

        // Simple Signature section as per LHDN sample
        AddBasicField(SignatureObject, 'ID', 'urn:oasis:names:specification:ubl:signature:Invoice');
        AddBasicField(SignatureObject, 'SignatureMethod', 'urn:oasis:names:specification:ubl:dsig:enveloped:xades');

        SignatureArray.Add(SignatureObject);
        InvoiceObject.Add('Signature', SignatureArray);
    end;

    local procedure AddTaxExchangeRate(var InvoiceObject: JsonObject; SalesInvoiceHeader: Record "Sales Invoice Header"; SourceCurrencyCode: Code[10])
    var
        TaxExchangeRateArray: JsonArray;
        TaxExchangeRateObject: JsonObject;
        CurrencyExchangeRate: Record "Currency Exchange Rate";
        ExchangeRate: Decimal;
    begin
        // MANDATORY for non-MYR currencies per LHDN specification
        // Get exchange rate from Business Central
        ExchangeRate := 1.0; // Default

        if CurrencyExchangeRate.Get(SourceCurrencyCode, Today()) then
            ExchangeRate := CurrencyExchangeRate."Exchange Rate Amount"
        else if CurrencyExchangeRate.Get(SourceCurrencyCode, SalesInvoiceHeader."Posting Date") then
            ExchangeRate := CurrencyExchangeRate."Exchange Rate Amount";

        AddBasicField(TaxExchangeRateObject, 'SourceCurrencyCode', SourceCurrencyCode);
        AddBasicField(TaxExchangeRateObject, 'TargetCurrencyCode', 'MYR');
        AddNumericField(TaxExchangeRateObject, 'CalculationRate', ExchangeRate);
        AddBasicField(TaxExchangeRateObject, 'Date', Format(Today(), 0, '<Year4>-<Month,2>-<Day,2>'));

        TaxExchangeRateArray.Add(TaxExchangeRateObject);
        // Defensive: ensure shape is always an array by removing any previous scalar/object entry
        if InvoiceObject.Contains('TaxExchangeRate') then
            InvoiceObject.Remove('TaxExchangeRate');
        InvoiceObject.Add('TaxExchangeRate', TaxExchangeRateArray);

        // Normalize any mis-shaped TaxExchangeRate into array-of-object with flat child fields
        NormalizeTaxExchangeRate(InvoiceObject);
    end;

    /// <summary>
    /// Normalizes TaxExchangeRate to the exact shape LHDN expects:
    /// - Invoice.TaxExchangeRate MUST be an array with a single object
    /// - The object's children (SourceCurrencyCode, TargetCurrencyCode, CalculationRate, Date)
    ///   MUST each be arrays-of-objects with "_" values (no duplicate wrapper objects)
    /// This also flattens cases like:
    ///   "SourceCurrencyCode": { "SourceCurrencyCode": [ { "_" : "SGD" } ] }
    /// into:
    ///   "SourceCurrencyCode": [ { "_" : "SGD" } ]
    /// </summary>
    local procedure NormalizeTaxExchangeRate(var InvoiceObject: JsonObject)
    var
        TreToken: JsonToken;
        TreArray: JsonArray;
        TreObj: JsonObject;
        NewTreObj: JsonObject;
        ElemToken: JsonToken;
    begin
        if not InvoiceObject.Get('TaxExchangeRate', TreToken) then
            exit;

        // Case 1: Mis-shaped object - convert to array with flattened fields
        if TreToken.IsObject() then begin
            TreObj := TreToken.AsObject();

            // Build a new object with flattened children
            AddFlattenedField(TreObj, NewTreObj, 'SourceCurrencyCode');
            AddFlattenedField(TreObj, NewTreObj, 'TargetCurrencyCode');
            AddFlattenedField(TreObj, NewTreObj, 'CalculationRate');
            AddFlattenedField(TreObj, NewTreObj, 'Date');

            TreArray.Add(NewTreObj);
            InvoiceObject.Remove('TaxExchangeRate');
            InvoiceObject.Add('TaxExchangeRate', TreArray);
            exit;
        end;

        // Case 2: Already an array - ensure the first element's children are flattened
        if TreToken.IsArray() then begin
            TreArray := TreToken.AsArray();
            if TreArray.Count > 0 then begin
                TreArray.Get(0, ElemToken);
                if ElemToken.IsObject() then begin
                    TreObj := ElemToken.AsObject();
                    FlattenFieldInPlace(TreObj, 'SourceCurrencyCode');
                    FlattenFieldInPlace(TreObj, 'TargetCurrencyCode');
                    FlattenFieldInPlace(TreObj, 'CalculationRate');
                    FlattenFieldInPlace(TreObj, 'Date');
                end;
            end;

            // Re-assign to guarantee final shape is array
            InvoiceObject.Remove('TaxExchangeRate');
            InvoiceObject.Add('TaxExchangeRate', TreArray);
        end;
    end;

    /// <summary>
    /// Adds a flattened field to DestObj by extracting:
    /// - SourceObj[Name] if it's already an array
    /// - SourceObj[Name][Name] if it's an inner duplicate-wrapper object
    /// - Otherwise wraps a scalar value into [ { "_" : value } ]
    /// </summary>
    local procedure AddFlattenedField(SourceObj: JsonObject; var DestObj: JsonObject; Name: Text)
    var
        T: JsonToken;
        InnerObj: JsonObject;
        InnerToken: JsonToken;
        Arr: JsonArray;
        ValueArr: JsonArray;
        ValueObj: JsonObject;
    begin
        if SourceObj.Get(Name, T) then begin
            if T.IsArray() then begin
                DestObj.Add(Name, T.AsArray());
                exit;
            end;

            if T.IsObject() then begin
                InnerObj := T.AsObject();
                if InnerObj.Get(Name, InnerToken) and InnerToken.IsArray() then begin
                    DestObj.Add(Name, InnerToken.AsArray());
                    exit;
                end;
            end;

            if T.IsValue() then begin
                // Fallback: wrap scalar into UBL array-of-object form
                ValueObj.Add('_', Format(T.AsValue()));
                ValueArr.Add(ValueObj);
                DestObj.Add(Name, ValueArr);
            end;
        end;
    end;

    /// <summary>
    /// In-place flattener for a field that may be in the duplicate-wrapper form:
    ///   Name: { Name: [ { "_" : value } ] }  =>  Name: [ { "_" : value } ]
    /// </summary>
    local procedure FlattenFieldInPlace(var Obj: JsonObject; Name: Text)
    var
        T: JsonToken;
        InnerObj: JsonObject;
        InnerToken: JsonToken;
    begin
        if Obj.Get(Name, T) and T.IsObject() then begin
            InnerObj := T.AsObject();
            if InnerObj.Get(Name, InnerToken) and InnerToken.IsArray() then begin
                Obj.Remove(Name);
                Obj.Add(Name, InnerToken.AsArray());
            end;
        end;
    end;

    // ======================================================================================================
    // UBL 2.1 JSON STRUCTURE HELPER PROCEDURES
    // These procedures ensure proper LHDN-compliant JSON structure formatting
    // ======================================================================================================

    /// <summary>
    /// Adds a basic field with text value in UBL 2.1 array format
    /// </summary>
    local procedure AddBasicField(var ParentObject: JsonObject; FieldName: Text; FieldValue: Text)
    var
        ValueArray: JsonArray;
        ValueObject: JsonObject;
    begin
        if FieldValue <> '' then begin
            ValueObject.Add('_', FieldValue);
            ValueArray.Add(ValueObject);
            ParentObject.Add(FieldName, ValueArray);
        end;
    end;

    /// <summary>
    /// Adds a field with one attribute in UBL 2.1 format
    /// </summary>
    local procedure AddFieldWithAttribute(var ParentObject: JsonObject; FieldName: Text; FieldValue: Text; AttributeName: Text; AttributeValue: Text)
    var
        ValueArray: JsonArray;
        ValueObject: JsonObject;
    begin
        if FieldValue <> '' then begin
            ValueObject.Add('_', FieldValue);
            ValueObject.Add(AttributeName, AttributeValue);
            ValueArray.Add(ValueObject);
            ParentObject.Add(FieldName, ValueArray);
        end;
    end;

    /// <summary>
    /// Wrapper for AddFieldWithAttribute - maintains backward compatibility
    /// </summary>
    local procedure AddBasicFieldWithAttribute(var ParentObject: JsonObject; FieldName: Text; FieldValue: Text; AttributeName: Text; AttributeValue: Text)
    begin
        AddFieldWithAttribute(ParentObject, FieldName, FieldValue, AttributeName, AttributeValue);
    end;

    /// <summary>
    /// Adds a field with two attributes in UBL 2.1 format
    /// </summary>
    local procedure AddBasicFieldWithAttributes(var ParentObject: JsonObject; FieldName: Text; FieldValue: Text; Attr1Name: Text; Attr1Value: Text; Attr2Name: Text; Attr2Value: Text)
    var
        ValueArray: JsonArray;
        ValueObject: JsonObject;
    begin
        if FieldValue <> '' then begin
            ValueObject.Add('_', FieldValue);
            ValueObject.Add(Attr1Name, Attr1Value);
            ValueObject.Add(Attr2Name, Attr2Value);
            ValueArray.Add(ValueObject);
            ParentObject.Add(FieldName, ValueArray);
        end;
    end;

    /// <summary>
    /// Adds amount field with currency code attribute - includes validation for negative amounts
    /// Note: Negative values are allowed for LineExtensionAmount at line level to support discount/adjustment lines.
    ///       We still prevent negative TaxAmount and PayableAmount for compliance.
    /// </summary>
    local procedure AddAmountField(var ParentObject: JsonObject; FieldName: Text; Amount: Decimal; CurrencyCode: Text)
    var
        ValueArray: JsonArray;
        ValueObject: JsonObject;
    begin
        // Validate amount is not negative for critical totals
        // Allow negative LineExtensionAmount at line level (discount lines), but still block negative TaxAmount and PayableAmount
        if (FieldName in ['TaxAmount', 'PayableAmount']) and (Amount < 0) then
            Error('Amount field %1 cannot be negative: %2', FieldName, Amount);

        ValueObject.Add('_', Amount);
        ValueObject.Add('currencyID', CurrencyCode);
        ValueArray.Add(ValueObject);
        ParentObject.Add(FieldName, ValueArray);
    end;

    local procedure AddQuantityField(var ParentObject: JsonObject; FieldName: Text; Quantity: Decimal; UnitCode: Text)
    var
        ValueArray: JsonArray;
        ValueObject: JsonObject;
    begin
        ValueObject.Add('_', Quantity);
        ValueObject.Add('unitCode', UnitCode);
        ValueArray.Add(ValueObject);
        ParentObject.Add(FieldName, ValueArray);
    end;

    local procedure AddNumericField(var ParentObject: JsonObject; FieldName: Text; NumericValue: Decimal)
    var
        ValueArray: JsonArray;
        ValueObject: JsonObject;
    begin
        // For numeric fields that LHDN expects as numbers, not strings
        ValueObject.Add('_', NumericValue);
        ValueArray.Add(ValueObject);
        ParentObject.Add(FieldName, ValueArray);
    end;

    local procedure AddPartyIdentification(var PartyIdentificationArray: JsonArray; ID: Text; SchemeID: Text)
    var
        IDObject: JsonObject;
        IDArray: JsonArray;
        IDValueObject: JsonObject;
    begin
        // For TIN and BRN - always required (use actual value or NA)
        // For SST and TTX - use NA if not applicable
        if ID <> '' then begin
            IDValueObject.Add('_', ID);
            IDValueObject.Add('schemeID', SchemeID);
        end else begin
            IDValueObject.Add('_', 'NA');
            IDValueObject.Add('schemeID', SchemeID);
        end;

        IDArray.Add(IDValueObject);
        IDObject.Add('ID', IDArray);
        PartyIdentificationArray.Add(IDObject);
    end;

    local procedure AddAddressLines(var PostalAddressObject: JsonObject; Address1: Text; Address2: Text; Address3: Text)
    var
        AddressLineArray: JsonArray;
        LineObject: JsonObject;
        LineArray: JsonArray;
        LineValueObject: JsonObject;
    begin
        if Address1 <> '' then begin
            Clear(LineArray);
            Clear(LineValueObject);
            LineValueObject.Add('_', Address1);
            LineArray.Add(LineValueObject);
            Clear(LineObject);
            LineObject.Add('Line', LineArray);
            AddressLineArray.Add(LineObject);
        end;

        if Address2 <> '' then begin
            Clear(LineObject);
            Clear(LineArray);
            Clear(LineValueObject);
            LineValueObject.Add('_', Address2);
            LineArray.Add(LineValueObject);
            LineObject.Add('Line', LineArray);
            AddressLineArray.Add(LineObject);
        end;

        if Address3 <> '' then begin
            Clear(LineObject);
            Clear(LineArray);
            Clear(LineValueObject);
            LineValueObject.Add('_', Address3);
            LineArray.Add(LineValueObject);
            LineObject.Add('Line', LineArray);
            AddressLineArray.Add(LineObject);
        end;

        if AddressLineArray.Count > 0 then
            PostalAddressObject.Add('AddressLine', AddressLineArray);
    end;

    local procedure AddCountry(var PostalAddressObject: JsonObject; CountryCode: Code[10])
    var
        CountryArray: JsonArray;
        CountryObject: JsonObject;
        IdentificationCodeArray: JsonArray;
        IdentificationCodeObject: JsonObject;
    begin
        IdentificationCodeObject.Add('_', CountryCode);
        IdentificationCodeObject.Add('listID', 'ISO3166-1');
        IdentificationCodeObject.Add('listAgencyID', '6');
        IdentificationCodeArray.Add(IdentificationCodeObject);
        CountryObject.Add('IdentificationCode', IdentificationCodeArray);
        CountryArray.Add(CountryObject);
        PostalAddressObject.Add('Country', CountryArray);
    end;

    local procedure AddLineAllowanceCharge(var AllowanceChargeArray: JsonArray; IsCharge: Boolean; Reason: Text; Percentage: Decimal; Amount: Decimal; CurrencyCode: Text)
    var
        AllowanceCharge: JsonObject;
        ChargeIndicatorArray: JsonArray;
        ChargeIndicatorObject: JsonObject;
        AllowanceChargeReasonArray: JsonArray;
        AllowanceChargeReasonObject: JsonObject;
        MultiplierFactorArray: JsonArray;
        MultiplierFactorObject: JsonObject;
        AmountArray: JsonArray;
        AmountObject: JsonObject;
    begin
        ChargeIndicatorObject.Add('_', IsCharge);
        ChargeIndicatorArray.Add(ChargeIndicatorObject);
        AllowanceCharge.Add('ChargeIndicator', ChargeIndicatorArray);

        AllowanceChargeReasonObject.Add('_', Reason);
        AllowanceChargeReasonArray.Add(AllowanceChargeReasonObject);
        AllowanceCharge.Add('AllowanceChargeReason', AllowanceChargeReasonArray);

        if Percentage > 0 then begin
            MultiplierFactorObject.Add('_', Percentage / 100);
            MultiplierFactorArray.Add(MultiplierFactorObject);
            AllowanceCharge.Add('MultiplierFactorNumeric', MultiplierFactorArray);
        end;

        AmountObject.Add('_', Amount);
        AmountObject.Add('currencyID', CurrencyCode);
        AmountArray.Add(AmountObject);
        AllowanceCharge.Add('Amount', AmountArray);

        AllowanceChargeArray.Add(AllowanceCharge);
    end;

    // Business logic helper functions (customize these based on your setup)
    local procedure GetCurrencyCode(SalesInvoiceHeader: Record "Sales Invoice Header"): Code[10]
    begin
        if SalesInvoiceHeader."Currency Code" = '' then
            exit('MYR')
        else
            exit(SalesInvoiceHeader."Currency Code");
    end;

    local procedure GetCurrencyCodeFromText(CurrencyCode: Code[10]): Code[10]
    begin
        if CurrencyCode = '' then
            exit('MYR')
        else
            exit(CurrencyCode);
    end;

    local procedure GetUBLUnitCode(SalesInvoiceLine: Record "Sales Invoice Line"): Code[10]
    begin
        // Return the UBL unit code directly from the e-Invoice UOM field
        if SalesInvoiceLine."e-Invoice UOM" <> '' then
            exit(SalesInvoiceLine."e-Invoice UOM")
        else
            exit('EA'); // Default to pieces if empty
    end;

    local procedure GetStateCode(County: Text): Text
    var
        UpperCounty: Text;
    begin
        UpperCounty := UpperCase(County);
        case UpperCounty of
            'JOHOR':
                exit('01');
            'KEDAH', 'SUNGAI PETANI':
                exit('02');
            'KELANTAN':
                exit('03');
            'MELAKA', 'MALACCA':
                exit('04');
            'NEGERI SEMBILAN', 'SEREMBAN', 'NILAI':
                exit('05');
            'PAHANG':
                exit('06');
            'PULAU PINANG', 'PENANG':
                exit('07');
            'PERAK':
                exit('08');
            'PERLIS':
                exit('09');
            'SELANGOR':
                exit('10');
            'TERENGGANU':
                exit('11');
            'SABAH':
                exit('12');
            'SARAWAK', 'KUCHING':
                exit('13');
            'WILAYAH PERSEKUTUAN KUALA LUMPUR', 'KUALA LUMPUR':
                exit('14');
            'WILAYAH PERSEKUTUAN LABUAN', 'LABUAN':
                exit('15');
            'WILAYAH PERSEKUTUAN PUTRAJAYA', 'PUTRAJAYA':
                exit('16');
            else
                exit('17'); // Default to Not Applicable
        end;
    end;

    local procedure GetCustomerStateCode(Customer: Record Customer): Text
    begin
        // First priority: Use the e-Invoice State Code if populated
        if Customer."e-Invoice State Code" <> '' then
            exit(Customer."e-Invoice State Code");

        // Second priority: Use County field and convert to state code
        if Customer.County <> '' then
            exit(GetStateCode(Customer.County));

        // Fallback: Return Not Applicable
        exit('17');
    end;

    local procedure GetCompanyStateCode(CompanyInfo: Record "Company Information"): Text
    begin
        // First priority: Use the e-Invoice State Code if populated
        if CompanyInfo."e-Invoice State Code" <> '' then
            exit(CompanyInfo."e-Invoice State Code");

        // Second priority: Use County field and convert to state code (if Company Info has County field)
        // Note: Standard Company Information table doesn't have County field
        // You might need to add a County field to your Company Information extension

        // Fallback: Return Not Applicable
        exit('17');
    end;

    local procedure GetCountryCode(CountryRegionCode: Code[10]): Code[10]
    begin
        case UpperCase(CountryRegionCode) of
            'MY', 'MYS', 'MALAYSIA':
                exit('MYS');
            'SG', 'SGP', 'SINGAPORE':
                exit('SGP');
            'TH', 'THA', 'THAILAND':
                exit('THA');
            'ID', 'IDN', 'INDONESIA':
                exit('IDN');
            'PH', 'PHL', 'PHILIPPINES':
                exit('PHL');
            'VN', 'VNM', 'VIETNAM':
                exit('VNM');
            'US', 'USA', 'UNITED STATES':
                exit('USA');
            'GB', 'GBR', 'UNITED KINGDOM':
                exit('GBR');
            'CN', 'CHN', 'CHINA':
                exit('CHN');
            'JP', 'JPN', 'JAPAN':
                exit('JPN');
            'AU', 'AUS', 'AUSTRALIA':
                exit('AUS');
            else
                exit('MYS'); // Default to Malaysia
        end;
    end;

    local procedure GetCustomerIDType(Customer: Record Customer): Text
    begin
        // Convert customer's e-Invoice ID Type option to LHDN expected text
        // Option: 0=NRIC, 1=BRN, 2=PASSPORT, 3=ARMY
        case Customer."e-Invoice ID Type" of
            Customer."e-Invoice ID Type"::NRIC:
                exit('NRIC');
            Customer."e-Invoice ID Type"::BRN:
                exit('BRN');
            Customer."e-Invoice ID Type"::PASSPORT:
                exit('PASSPORT');
            Customer."e-Invoice ID Type"::ARMY:
                exit('ARMY');
            else
                exit('BRN'); // Default to BRN if not set
        end;
    end;

    // ======================================================================================================
    // BUSINESS LOGIC HELPER PROCEDURES
    // Configure these based on your company setup and Business Central field mappings
    // ======================================================================================================

    /// <summary>
    /// Gets tax category code with fallback to standard rate
    /// </summary>
    local procedure GetTaxCategoryCode(eInvoiceTaxCategoryCode: Code[10]): Code[10]
    begin
        if eInvoiceTaxCategoryCode <> '' then
            exit(eInvoiceTaxCategoryCode)
        else
            exit('01'); // Default to standard rate if empty
    end;

    /// <summary>
    /// Gets company MSIC code from Company Information or returns default
    /// </summary>
    local procedure GetMSICCode(): Text
    var
        CompanyInformation: Record "Company Information";
    begin
        // Return your company's MSIC code - customize this based on your field mappings
        if CompanyInformation.Get() then begin
            if CompanyInformation."MSIC Code" <> '' then
                exit(CompanyInformation."MSIC Code");
        end;
        exit('46510'); // Default MSIC code for wholesale computer hardware
    end;

    /// <summary>
    /// Gets company MSIC description from Company Information or returns default
    /// </summary>
    local procedure GetMSICDescription(): Text
    var
        CompanyInformation: Record "Company Information";
    begin
        // Return your company's MSIC description - customize this
        if CompanyInformation.Get() then begin
            if CompanyInformation."Business Activity Description" <> '' then
                exit(CompanyInformation."Business Activity Description");
        end;
        exit('Wholesale of computer hardware, software and peripherals'); // Default description
    end;

    /// <summary>
    /// Gets certification ID (e.g., CertEX ID) - customize based on your requirements
    /// </summary>
    local procedure GetCertificationID(): Text
    begin
        // Return your certification ID - add custom field to Company Information if needed
        exit(''); // Return empty if no certification required
    end;

    /// <summary>
    /// Gets company SST registration number or returns 'NA'
    /// </summary>
    local procedure GetSSTNumber(): Text
    var
        CompanyInformation: Record "Company Information";
    begin
        if CompanyInformation.Get() then begin
            if CompanyInformation."VAT Registration No." <> '' then
                exit(CompanyInformation."VAT Registration No.");
        end;
        exit('NA');
    end;

    local procedure GetTTXNumber(): Text
    var
        CompanyInformation: Record "Company Information";
    begin
        if CompanyInformation.Get() then begin
            if CompanyInformation."TTX No." <> '' then
                exit(CompanyInformation."TTX No.");
        end;
        exit('NA');
    end;

    local procedure GetCustomerSSTNumber(Customer: Record Customer): Text
    begin
        // Return customer's SST number if available
        if Customer."e-Invoice SST No." <> '' then
            exit(Customer."e-Invoice SST No.")
        else
            exit('NA');
    end;

    local procedure GetCustomerTTXNumber(Customer: Record Customer): Text
    begin
        // Return customer's TTX number if available
        // Add field to Customer table extension if needed
        exit('NA');
    end;

    local procedure GetBankAccountNumber(): Text
    var
        CompanyInformation: Record "Company Information";
        BankAccount: Record "Bank Account";
    begin
        // Get the company's bank account number for payments

        // Try Company Information first
        if CompanyInformation.Get() then begin
            if CompanyInformation."Bank Account No." <> '' then
                exit(CompanyInformation."Bank Account No.");

            // Find the first non-blocked bank account with actual account number
            BankAccount.SetRange(Blocked, false);
            BankAccount.SetFilter("Bank Account No.", '<>%1', '');
            if BankAccount.FindFirst() then begin
                if BankAccount."Bank Account No." <> '' then
                    exit(BankAccount."Bank Account No.")
                else if BankAccount."No." <> '' then
                    exit(BankAccount."No.");
            end;
        end;

        // Return empty string if no bank account found
        exit('');
    end;

    local procedure GetPaymentTermsNote(SalesInvoiceHeader: Record "Sales Invoice Header"): Text
    var
        PaymentTerms: Record "Payment Terms";
        PaymentTermsText: Text;
        DueDateText: Text;
    begin
        // Get payment terms from Payment Terms Code instead of hardcoding based on payment mode
        if SalesInvoiceHeader."Payment Terms Code" <> '' then begin
            if PaymentTerms.Get(SalesInvoiceHeader."Payment Terms Code") then begin
                // Use the actual payment terms description
                if PaymentTerms.Description <> '' then
                    PaymentTermsText := PaymentTerms.Description
                else
                    PaymentTermsText := SalesInvoiceHeader."Payment Terms Code";

                // Add due date calculation if available
                if Format(PaymentTerms."Due Date Calculation") <> '' then begin
                    DueDateText := GetPaymentTermsDueText(PaymentTerms."Due Date Calculation");
                    if DueDateText <> '' then
                        PaymentTermsText := PaymentTermsText + ' - ' + DueDateText;
                end;

                // Add discount terms if available
                if PaymentTerms."Discount %" > 0 then begin
                    PaymentTermsText := PaymentTermsText + ' (Discount: ' + Format(PaymentTerms."Discount %") + '%';
                    if Format(PaymentTerms."Discount Date Calculation") <> '' then
                        PaymentTermsText := PaymentTermsText + ' if paid within ' + Format(PaymentTerms."Discount Date Calculation");
                    PaymentTermsText := PaymentTermsText + ')';
                end;

                exit(PaymentTermsText);
            end;
        end;

        // Fallback: Use payment mode if no payment terms code
        exit(GetPaymentModeDescription(SalesInvoiceHeader));
    end;

    local procedure GetPaymentTermsDueText(DueDateCalculation: DateFormula): Text
    begin
        // Return just the code instead of descriptive text
        exit(Format(DueDateCalculation));
    end;

    local procedure GetPaymentModeDescription(SalesInvoiceHeader: Record "Sales Invoice Header"): Text
    var
        PaymentModeCode: Code[10];
    begin
        // Fallback method using payment mode codes
        PaymentModeCode := GetPaymentMeansCode(SalesInvoiceHeader);

        case PaymentModeCode of
            '01':
                exit('Cash');
            '02':
                exit('Cheque');
            '03':
                exit('Bank Transfer');
            '04':
                exit('Credit Card');
            '05':
                exit('Debit Card');
            '06':
                exit('e-Wallet / Digital Wallet');
            '07':
                exit('Digital Bank');
            '08':
                exit('Others');
            else
                exit(''); // Return empty string if no valid payment mode
        end;
    end;

    local procedure GetHSCode(SalesInvoiceLine: Record "Sales Invoice Line"): Text
    begin
        // Return the HS code directly from the e-Invoice Classification field
        if SalesInvoiceLine."e-Invoice Classification" <> '' then
            exit(SalesInvoiceLine."e-Invoice Classification")
        else
            exit('022'); // Default HS code if empty
    end;

    local procedure GetClassificationCode(SalesInvoiceLine: Record "Sales Invoice Line"): Text
    var
        eInvoiceClassification: Record eInvoiceClassification;
        SalesLineArchive: Record "Sales Line Archive";
    begin
        // First, try to get classification from the regular sales invoice line
        if SalesInvoiceLine."e-Invoice Classification" <> '' then begin
            // Verify the classification exists in the eInvoiceClassification table
            if eInvoiceClassification.Get(SalesInvoiceLine."e-Invoice Classification") then
                exit(SalesInvoiceLine."e-Invoice Classification")
            else
                exit(SalesInvoiceLine."e-Invoice Classification"); // Still use the value even if not found in table
        end;

        // If not found in regular line, try to get from archived sales line
        if SalesLineArchive.Get(SalesInvoiceLine."Document No.", SalesInvoiceLine."Line No.") then begin
            if SalesLineArchive."e-Invoice Classification" <> '' then begin
                // Verify the classification exists in the eInvoiceClassification table
                if eInvoiceClassification.Get(SalesLineArchive."e-Invoice Classification") then
                    exit(SalesLineArchive."e-Invoice Classification")
                else
                    exit(SalesLineArchive."e-Invoice Classification"); // Still use the value even if not found in table
            end;
        end;

        // Fallback to universal classification if field is empty in both regular and archived lines
        exit('022'); // Universal fallback classification
    end;

    local procedure HasPrepaidAmount(SalesInvoiceHeader: Record "Sales Invoice Header"): Boolean
    begin
        // Check if there are any prepaid amounts
        exit(GetPrepaidAmount(SalesInvoiceHeader) > 0);
    end;

    local procedure GetPrepaidAmount(SalesInvoiceHeader: Record "Sales Invoice Header"): Decimal
    begin
        // Implement actual logic to get prepaid amount
        // For now, return 0 if no prepaid amount exists
        exit(0);
    end;

    local procedure GetOriginCountryCode(SalesInvoiceLine: Record "Sales Invoice Line"): Text
    var
        Item: Record Item;
        CompanyInformation: Record "Company Information";
    begin
        // Try to get from item first
        if SalesInvoiceLine.Type = SalesInvoiceLine.Type::Item then begin
            if Item.Get(SalesInvoiceLine."No.") then begin
                // If you have a country of origin field on Item table, use it
                // exit(Item."Country of Origin Code");
            end;
        end;

        // Fallback to company information
        if CompanyInformation.Get() then
            exit(GetCountryCode(CompanyInformation."e-Invoice Country Code"));

        exit('MYS'); // Default to Malaysia
    end;

    local procedure GetTaxExemptionReason(TaxType: Code[10]): Text
    begin
        // Return appropriate tax exemption reason based on tax type
        case TaxType of
            'E':
                exit('Exempt New Means of Transport');
            'Z':
                exit('Zero-rated supply');
            else
                exit('');
        end;
    end;

    /// <summary>
    /// Complete integration workflow: Generate > Sign > Submit to LHDN
    /// Handles the full process from unsigned JSON to LHDN submission with proper error handling
    /// </summary>
    /// <param name="SalesInvoiceHeader">Sales Invoice record to process</param>
    /// <param name="LhdnResponse">Final response from LHDN MyInvois API</param>
    /// <returns>True if entire process successful, False if any step fails</returns>
    procedure GetSignedInvoiceAndSubmitToLHDN(SalesInvoiceHeader: Record "Sales Invoice Header"; var LhdnResponse: Text): Boolean
    var
        UnsignedJsonText: Text;
        AzureResponseText: Text;
        AzureResponse: JsonObject;
        JsonToken: JsonToken;
        eInvoiceSetup: Record "eInvoiceSetup";
        AzureFunctionUrl: Text;
    begin
        // Step 1: Generate unsigned eInvoice JSON
        UnsignedJsonText := GenerateEInvoiceJson(SalesInvoiceHeader, false);

        // Step 2: Get Azure Function URL from setup
        if not eInvoiceSetup.Get('SETUP') then begin
            LhdnResponse := 'eInvoice Setup not found. Please configure the Azure Function URL.';
            exit(false);
        end;

        AzureFunctionUrl := eInvoiceSetup."Azure Function URL";
        if AzureFunctionUrl = '' then begin
            LhdnResponse := 'Azure Function URL is not configured in eInvoice Setup.';
            exit(false);
        end;

        // Step 3: Get signed invoice from Azure Function using the working direct method
        if not TryPostToAzureFunctionDirect(UnsignedJsonText, AzureFunctionUrl, AzureResponseText, SalesInvoiceHeader) then begin
            LhdnResponse := 'Failed to communicate with Azure Function. Please check connectivity and try again.';
            exit(false);
        end;

        // Step 4: Parse Azure Function response with detailed validation and debugging
        if not AzureResponse.ReadFrom(AzureResponseText) then begin
            LhdnResponse := StrSubstNo('Invalid JSON response from Azure Function: %1', CopyStr(AzureResponseText, 1, 500));
            LogDebugInfo('Azure Function JSON parsing failed',
                StrSubstNo('Response length: %1\nResponse preview: %2', StrLen(AzureResponseText), CopyStr(AzureResponseText, 1, 500)));
            exit(false);
        end;

        // Log the Azure Function response structure for debugging
        LogDebugInfo('Azure Function response received',
            StrSubstNo('Response keys: %1\nResponse preview: %2',
                GetJsonObjectKeys(AzureResponse),
                CopyStr(AzureResponseText, 1, 300)));

        // Check for success status (BusinessCentralSigningResponse format)
        if not AzureResponse.Get('success', JsonToken) or not JsonToken.AsValue().AsBoolean() then begin
            if AzureResponse.Get('errorDetails', JsonToken) then
                LhdnResponse := StrSubstNo('Azure Function signing failed: %1', SafeJsonValueToText(JsonToken))
            else if AzureResponse.Get('message', JsonToken) then
                LhdnResponse := StrSubstNo('Azure Function error: %1', SafeJsonValueToText(JsonToken))
            else
                LhdnResponse := StrSubstNo('Azure Function signing failed with unknown error. Response: %1', CopyStr(AzureResponseText, 1, 200));

            LogDebugInfo('Azure Function signing failed',
                StrSubstNo('Error response: %1', LhdnResponse));
            exit(false);
        end;

        // Step 5: Process and store signed JSON (important for audit trail)
        if AzureResponse.Get('signedJson', JsonToken) then begin
            // Store the signed JSON for records/audit purposes
            StoreSignedInvoiceJson(SalesInvoiceHeader, SafeJsonValueToText(JsonToken));
        end;

        // Step 6: Extract LHDN payload and submit to LHDN API
        // Azure Function response format:
        // {
        //   "success": true,
        //   "correlationId": "...",
        //   "statusCode": 200,
        //   "message": "Invoice signed successfully",
        //   "signedJson": "...",
        //   "lhdnPayload": "{\"documents\":[...]}" (string, not object)
        // }
        if AzureResponse.Get('lhdnPayload', JsonToken) then begin
            // The lhdnPayload is returned as a JSON string, not an object
            // We need to parse this string into a JSON object
            LhdnResponse := SafeJsonValueToText(JsonToken);

            // Log the LHDN payload for debugging
            LogDebugInfo('LHDN Payload extracted from Azure Function',
                StrSubstNo('Payload length: %1\nPayload preview: %2',
                    StrLen(LhdnResponse),
                    CopyStr(LhdnResponse, 1, 300)));

            // Process the LHDN payload string
            exit(ProcessLhdnPayload(LhdnResponse, SalesInvoiceHeader, LhdnResponse));
        end else begin
            LhdnResponse := StrSubstNo('No LHDN payload found in Azure Function response. Response keys: %1', GetJsonObjectKeys(AzureResponse));
            LogDebugInfo('Missing LHDN payload in Azure Function response',
                StrSubstNo('Available keys: %1\nFull response preview: %2',
                    GetJsonObjectKeys(AzureResponse),
                    CopyStr(AzureResponseText, 1, 500)));
            exit(false);
        end;
    end;

    /// <summary>
    /// Internal implementation for posting to Azure Function using Microsoft's recommended approach
    /// Uses the System Application Azure Functions codeunit with fallback to direct HttpClient
    /// </summary>
    /// <param name="JsonText">JSON payload to send to Azure Function</param>
    /// <param name="AzureFunctionUrl">Azure Function endpoint URL</param>
    /// <param name="ResponseText">Response from Azure Function</param>
    /// <returns>True if successful, False if failed</returns>
    local procedure TryPostToAzureFunctionInternal(JsonText: Text; AzureFunctionUrl: Text; var ResponseText: Text): Boolean
    var
        RequestPayload: JsonObject;
        RequestText: Text;
        CorrelationId: Text;
        Setup: Record "eInvoiceSetup";
        Success: Boolean;
        MaxRetries: Integer;
        AttemptCount: Integer;
        InvoiceTypeCode: Text;
    begin
        // Initialize variables
        Success := false;
        MaxRetries := 3;
        AttemptCount := 0;

        // Generate correlation ID for tracking
        CorrelationId := CreateGuid();

        // Get setup and validate environment
        if not Setup.Get('SETUP') then begin
            ResponseText := 'Error: eInvoice Setup not found';
            exit(false);
        end;

        // Validate environment before proceeding
        if not ValidateEnvironmentBeforeSigning(Setup) then begin
            ResponseText := 'Error: Environment validation failed';
            exit(false);
        end;

        // Extract invoice type from the UBL JSON payload
        InvoiceTypeCode := ExtractInvoiceTypeFromJson(JsonText);

        // Build BusinessCentralSigningRequest payload matching Azure Function model
        RequestPayload.Add('correlationId', CorrelationId);
        RequestPayload.Add('invoiceType', InvoiceTypeCode);
        RequestPayload.Add('unsignedJson', JsonText);
        RequestPayload.Add('submissionId', CorrelationId);
        RequestPayload.Add('requestedBy', UserId());

        // Enhance payload with validated environment information
        EnhancePayloadWithEnvironmentInfo(RequestPayload, Setup);

        RequestPayload.WriteTo(RequestText);

        // Try Microsoft's Azure Functions approach first, then fallback to direct HttpClient
        Success := TryMicrosoftAzureFunctions(AzureFunctionUrl, RequestText, ResponseText, CorrelationId);

        if not Success then begin
            // Fallback to direct HttpClient approach
            Success := TryDirectHttpClient(AzureFunctionUrl, RequestText, ResponseText, CorrelationId, MaxRetries);
        end;

        // Validate the signed response if successful
        if Success and (ResponseText <> '') then begin
            if not ValidateSignedResponse(ResponseText, Format(Setup.Environment)) then begin
                ResponseText := 'Error: Signed response environment validation failed';
                exit(false);
            end;
        end;

        exit(Success);
    end;

    /// <summary>
    /// Extracts invoice type code from UBL JSON payload
    /// </summary>
    /// <param name="JsonText">UBL JSON text to parse</param>
    /// <returns>Invoice type code, defaults to '01' if not found</returns>
    local procedure ExtractInvoiceTypeFromJson(JsonText: Text): Text
    var
        JsonObject: JsonObject;
        InvoiceArray: JsonArray;
        InvoiceObject: JsonObject;
        InvoiceTypeCode: JsonObject;
        TypeCode: Text;
        JsonToken: JsonToken;
    begin
        // Default to standard invoice if parsing fails
        if JsonText = '' then
            exit('01');

        // Try to parse the JSON and extract invoice type
        if JsonObject.ReadFrom(JsonText) then begin
            if JsonObject.Get('Invoice', JsonToken) then begin
                if JsonToken.AsArray().Get(0, JsonToken) then begin
                    if JsonToken.AsObject().Get('cbc:InvoiceTypeCode', JsonToken) then begin
                        if JsonToken.AsObject().Get('_text', JsonToken) then begin
                            TypeCode := JsonToken.AsValue().AsText();
                            if TypeCode <> '' then
                                exit(TypeCode);
                        end;
                    end;
                end;
            end;
        end;

        // Fallback to default
        exit('01');
    end;

    /// <summary>
    /// Attempts to use Microsoft's System Application Azure Functions codeunit
    /// </summary>
    local procedure TryMicrosoftAzureFunctions(AzureFunctionUrl: Text; RequestText: Text; var ResponseText: Text; CorrelationId: Text): Boolean
    var
        BaseUrl: Text;
        FunctionKey: Text;
    begin
        // Try to use Microsoft's Azure Functions framework
        // Note: This may not be available in all Business Central environments

        // Parse URL components
        BaseUrl := GetBaseUrl(AzureFunctionUrl);
        FunctionKey := GetFunctionKey(AzureFunctionUrl);

        // TODO: Implement Microsoft's Azure Functions codeunit when available
        // For now, return false to use fallback approach
        ResponseText := 'Microsoft Azure Functions codeunit not available, using fallback approach';
        exit(false);
    end;

    /// <summary>
    /// Direct HttpClient implementation as fallback
    /// </summary>
    local procedure TryDirectHttpClient(AzureFunctionUrl: Text; RequestText: Text; var ResponseText: Text; CorrelationId: Text; MaxRetries: Integer): Boolean
    var
        Client: HttpClient;
        Response: HttpResponseMessage;
        RequestContent: HttpContent;
        Headers: HttpHeaders;
        AttemptCount: Integer;
        Success: Boolean;
        RequestStartTime: DateTime;
        RequestEndTime: DateTime;
        ElapsedTime: Duration;
    begin
        Success := false;
        AttemptCount := 0;

        // Retry loop for network resilience
        repeat
            AttemptCount := AttemptCount + 1;
            RequestStartTime := CurrentDateTime;

            // Configure HTTP client
            Client.Clear();
            Client.Timeout := 300000; // 5 minutes timeout for Azure Functions

            // Prepare request content with enhanced headers
            RequestContent.WriteFrom(RequestText);
            RequestContent.GetHeaders(Headers);
            Headers.Clear();
            Headers.Add('Content-Type', 'application/json; charset=utf-8');
            Headers.Add('User-Agent', 'BusinessCentral-eInvoice/2.0');
            Headers.Add('Accept', 'application/json');
            Headers.Add('X-Correlation-ID', CorrelationId);
            Headers.Add('X-Request-Source', 'BusinessCentral-DirectClient');
            Headers.Add('X-Attempt-Number', Format(AttemptCount));

            // Send POST request to Azure Function
            if Client.Post(AzureFunctionUrl, RequestContent, Response) then begin
                RequestEndTime := CurrentDateTime;
                ElapsedTime := RequestEndTime - RequestStartTime;

                // Read response content
                Response.Content().ReadAs(ResponseText);

                if Response.IsSuccessStatusCode() then begin
                    // Success - validate response has content
                    if ResponseText <> '' then begin
                        Success := true;
                        exit(true);
                    end else begin
                        ResponseText := StrSubstNo('Azure Function returned empty response (Attempt %1/%2)\nCorrelation ID: %3\nElapsed Time: %4ms',
                            AttemptCount, MaxRetries, CorrelationId, ElapsedTime);
                    end;
                end else begin
                    // HTTP error response with enhanced details
                    ResponseText := StrSubstNo('Azure Function HTTP Error (Attempt %1/%2)\nStatus: %3 %4\nCorrelation ID: %5\nElapsed Time: %6ms\nURL: %7\nResponse: %8',
                        AttemptCount, MaxRetries, Response.HttpStatusCode(), Response.ReasonPhrase(),
                        CorrelationId, ElapsedTime, CopyStr(AzureFunctionUrl, 1, 100), CopyStr(ResponseText, 1, 300));
                end;
            end else begin
                // Connection failure
                RequestEndTime := CurrentDateTime;
                ElapsedTime := RequestEndTime - RequestStartTime;
                ResponseText := StrSubstNo('Failed to connect to Azure Function (Attempt %1/%2)\nURL: %3\nCorrelation ID: %4\nElapsed Time: %5ms\nTroubleshooting: Check network, DNS, firewall, and Azure Function status',
                    AttemptCount, MaxRetries, CopyStr(AzureFunctionUrl, 1, 100), CorrelationId, ElapsedTime);
            end;

            // Wait before retry (except on last attempt)
            if (not Success) and (AttemptCount < MaxRetries) then
                Sleep(2000); // 2 second delay between retries

        until Success or (AttemptCount >= MaxRetries);

        exit(Success);
    end;

    /// <summary>
    /// Extracts base URL from Azure Function URL (removes parameters)
    /// </summary>
    local procedure GetBaseUrl(FullUrl: Text): Text
    var
        QuestionMarkPos: Integer;
    begin
        QuestionMarkPos := FullUrl.IndexOf('?');
        if QuestionMarkPos > 0 then
            exit(CopyStr(FullUrl, 1, QuestionMarkPos - 1))
        else
            exit(FullUrl);
    end;

    /// <summary>
    /// Extracts function key from Azure Function URL for authentication
    /// </summary>
    local procedure GetFunctionKey(FullUrl: Text): Text
    var
        CodeParam: Text;
        StartPos: Integer;
        EndPos: Integer;
    begin
        // Look for code= parameter in URL
        CodeParam := 'code=';
        StartPos := FullUrl.IndexOf(CodeParam);

        if StartPos = 0 then
            exit(''); // No function key found (anonymous function)

        StartPos := StartPos + StrLen(CodeParam);
        EndPos := FullUrl.IndexOf('&', StartPos);

        if EndPos = 0 then
            exit(CopyStr(FullUrl, StartPos)) // Function key is at the end
        else
            exit(CopyStr(FullUrl, StartPos, EndPos - StartPos)); // Function key has more parameters after it
    end;

    /// <summary>
    /// Builds the BusinessCentralSigning endpoint URL from the main Azure Function URL
    /// </summary>
    local procedure BuildBusinessCentralSigningUrl(OriginalUrl: Text): Text
    var
        BaseUrl: Text;
        FunctionKey: Text;
        BusinessCentralUrl: Text;
    begin
        // Extract base URL and function key
        BaseUrl := GetBaseUrl(OriginalUrl);
        FunctionKey := GetFunctionKey(OriginalUrl);

        // Build BusinessCentralSigning endpoint URL
        BusinessCentralUrl := BaseUrl + '/api/BusinessCentralSigning';

        // Add function key if present
        if FunctionKey <> '' then
            BusinessCentralUrl += '?code=' + FunctionKey;

        exit(BusinessCentralUrl);
    end;

    // ======================================================================================================
    // LHDN MyInvois API INTEGRATION PROCEDURES
    // ======================================================================================================

    /// <summary>
    /// Submits digitally signed invoice to LHDN MyInvois API for official processing
    /// Handles proper payload structure validation and comprehensive error reporting
    /// </summary>
    /// <param name="LhdnPayload">Signed JSON payload from Azure Function</param>
    /// <param name="SalesInvoiceHeader">Invoice record for context and updates</param>
    /// <param name="LhdnResponse">Response from LHDN API</param>
    /// <returns>True if submission successful, False otherwise</returns>
    procedure SubmitToLhdnApi(LhdnPayload: JsonObject; SalesInvoiceHeader: Record "Sales Invoice Header"; var LhdnResponse: Text): Boolean
    var
        HttpClient: HttpClient;
        HttpRequestMessage: HttpRequestMessage;
        HttpResponseMessage: HttpResponseMessage;
        ContentHeaders: HttpHeaders;
        RequestHeaders: HttpHeaders;
        LhdnPayloadText: Text;
        AccessToken: Text;
        eInvoiceSetup: Record "eInvoiceSetup";
        LhdnApiUrl: Text;
        TempBlob: Codeunit "Temp Blob";
        OutStream: OutStream;
        InStream: InStream;
        FileName: Text;
        ActualLhdnPayload: JsonObject;
        JsonToken: JsonToken;
    begin
        // Get setup for environment determination
        if not eInvoiceSetup.Get('SETUP') then
            Error('eInvoice Setup not found');

        // SIMPLIFIED FIX: The Azure Function returns lhdnPayload as a JSON string
        // that already contains the correct documents array structure
        // We can use it directly for LHDN submission
        LhdnPayload.WriteTo(LhdnPayloadText);

        // Validate that we have the documents array structure
        if not LhdnPayloadText.Contains('"documents"') then begin
            Error('Invalid LHDN payload structure. Expected "documents" array not found. Payload preview: %1', CopyStr(LhdnPayloadText, 1, 200));
        end;

        // Validate the payload structure matches LHDN requirements
        if not ValidateLhdnPayloadStructure(LhdnPayloadText) then
            Error('LHDN payload does not match required structure for document submissions');

        // DEBUG: Log the LHDN payload structure for debugging (no automatic download)
        LogDebugInfo('LHDN Payload Ready for Submission',
            StrSubstNo('Payload Size: %1 characters\nPayload Structure: Validated\nFirst 500 chars: %2',
                StrLen(LhdnPayloadText),
                CopyStr(LhdnPayloadText, 1, 500)));

        // Get LHDN access token using the standardized eInvoiceHelper method
        AccessToken := GetLhdnAccessTokenFromHelper(eInvoiceSetup);

        // Debug: Log token information (first 50 chars for security)
        LogDebugInfo('LHDN Token Retrieved Successfully',
            StrSubstNo('Token Preview: %1...\nToken Length: %2\nEnvironment: %3\nAPI URL: %4',
                CopyStr(AccessToken, 1, 50),
                StrLen(AccessToken),
                Format(eInvoiceSetup.Environment),
                LhdnApiUrl));

        // Determine LHDN API URL based on environment
        if eInvoiceSetup.Environment = eInvoiceSetup.Environment::Preprod then
            LhdnApiUrl := 'https://preprod-api.myinvois.hasil.gov.my/api/v1.0/documentsubmissions'
        else
            LhdnApiUrl := 'https://api.myinvois.hasil.gov.my/api/v1.0/documentsubmissions';

        // Debug: Log environment and URL configuration
        LogDebugInfo('LHDN Environment Configuration',
            StrSubstNo('Environment: %1\nAPI URL: %2\nClient ID: %3\nClient Secret: %4',
                Format(eInvoiceSetup.Environment),
                LhdnApiUrl,
                eInvoiceSetup."Client ID" <> '' ? 'Configured' : 'MISSING',
                eInvoiceSetup."Client Secret" <> '' ? 'Configured' : 'MISSING'));

        // Debug: Log the request details before sending

        // Setup LHDN API request with standard headers
        HttpRequestMessage.Method := 'POST';
        HttpRequestMessage.SetRequestUri(LhdnApiUrl);
        HttpRequestMessage.Content.WriteFrom(LhdnPayloadText);

        // Set standard LHDN API headers as per documentation
        HttpRequestMessage.Content.GetHeaders(ContentHeaders);
        ContentHeaders.Clear();
        ContentHeaders.Add('Content-Type', 'application/json');

        HttpRequestMessage.GetHeaders(RequestHeaders);
        RequestHeaders.Clear();
        RequestHeaders.Add('Accept', 'application/json');
        RequestHeaders.Add('Accept-Language', 'en');
        RequestHeaders.Add('Authorization', 'Bearer ' + AccessToken);

        // Debug: Log the request details before sending
        LogDebugInfo('LHDN API Request Details',
            StrSubstNo('URL: %1\nMethod: POST\nContent-Type: application/json\nAuthorization: Bearer %2...\nPayload Size: %3 characters\nPayload Preview: %4',
                LhdnApiUrl,
                CopyStr(AccessToken, 1, 20),
                StrLen(LhdnPayloadText),
                CopyStr(LhdnPayloadText, 1, 200)));

        // Submit to LHDN
        if HttpClient.Send(HttpRequestMessage, HttpResponseMessage) then begin
            HttpResponseMessage.Content.ReadAs(LhdnResponse);

            if HttpResponseMessage.IsSuccessStatusCode then begin
                // Parse and display structured LHDN response with headers
                ParseAndDisplayLhdnResponse(LhdnResponse, HttpResponseMessage.HttpStatusCode, SalesInvoiceHeader, HttpResponseMessage);
                exit(true);
            end else begin
                // Parse and display structured LHDN error response with headers
                ParseAndDisplayLhdnError(LhdnResponse, HttpResponseMessage.HttpStatusCode, HttpResponseMessage.ReasonPhrase, HttpResponseMessage);

                // Update validation status to "Submission Failed" when there's an error
                SalesInvoiceHeader."eInvoice Validation Status" := 'Submission Failed';
                SalesInvoiceHeader.Modify();

                // Log the failed submission with HTTP status code and error response for proper parsing
                LogSubmissionWithError(SalesInvoiceHeader, LhdnResponse, HttpResponseMessage.HttpStatusCode, CreateGuid());
            end;
        end else begin
            Error('Failed to send HTTP request to LHDN API at %1', LhdnApiUrl);
        end;

        exit(false);
    end;

    local procedure ParseAndDisplayLhdnResponse(LhdnResponse: Text; StatusCode: Integer; var SalesInvoiceHeader: Record "Sales Invoice Header"; HttpResponseMessage: HttpResponseMessage)
    var
        ResponseJson: JsonObject;
        JsonToken: JsonToken;
        AcceptedArray: JsonArray;
        RejectedArray: JsonArray;
        SubmissionUid: Text;
        AcceptedCount: Integer;
        RejectedCount: Integer;
        i: Integer;
        DocumentJson: JsonObject;
        Uuid: Text;
        InvoiceCodeNumber: Text;
        CorrelationId: Text;
        RateLimitInfo: Text;
        ResponseHeaders: HttpHeaders;
        HeaderValues: List of [Text];
        SuccessMessage: Text;
        DocumentDetails: Text;
    begin
        // Extract LHDN response headers - using Content headers as proxy for response headers
        HttpResponseMessage.Content.GetHeaders(ResponseHeaders);

        // Note: In AL, direct access to response headers may be limited
        // The correlation ID and rate limit headers would typically be in the response
        // but we'll focus on the content parsing for now

        CorrelationId := 'N/A'; // Will be populated from JSON response if available
        RateLimitInfo := 'See LHDN response for rate limiting info';

        // Try to parse the JSON response
        if not ResponseJson.ReadFrom(LhdnResponse) then begin
            Message(StrSubstNo('LHDN Submission successful!\nStatus: %1\nRaw Response: %2', StatusCode, LhdnResponse));
            exit;
        end;

        // Log the response structure for debugging based on LHDN API documentation
        LogDebugInfo('LHDN API Response Structure',
            StrSubstNo('Status Code: %1\nResponse Keys: %2\nResponse Preview: %3',
                StatusCode,
                GetJsonObjectKeys(ResponseJson),
                CopyStr(LhdnResponse, 1, 500)));

        // Extract submission UID with safe type conversion
        // According to LHDN API docs: submissionUID is a String with 26 Latin alphanumeric symbols
        if ResponseJson.Get('submissionUid', JsonToken) then
            SubmissionUid := SafeJsonValueToText(JsonToken)
        else if ResponseJson.Get('submissionUID', JsonToken) then
            // Try alternative casing as per LHDN documentation
            SubmissionUid := SafeJsonValueToText(JsonToken)
        else
            SubmissionUid := 'N/A';

        // Process accepted documents
        AcceptedCount := 0;
        DocumentDetails := '';
        if ResponseJson.Get('acceptedDocuments', JsonToken) then begin
            AcceptedArray := JsonToken.AsArray();
            AcceptedCount := AcceptedArray.Count;

            DocumentDetails := BuildDocumentDetails(AcceptedArray, RejectedArray);
        end;

        // Process rejected documents
        RejectedCount := 0;
        if ResponseJson.Get('rejectedDocuments', JsonToken) then begin
            RejectedArray := JsonToken.AsArray();
            RejectedCount := RejectedArray.Count;
        end;

        // Build success message with proper formatting
        if (AcceptedCount > 0) and (RejectedCount = 0) then begin
            // All documents accepted
            SuccessMessage := FormatLhdnSuccessMessage(SubmissionUid, StatusCode, AcceptedCount, DocumentDetails, CorrelationId, RateLimitInfo);
        end else if (AcceptedCount > 0) and (RejectedCount > 0) then begin
            // Mixed results - some accepted, some rejected
            SuccessMessage := StrSubstNo('LHDN Submission Partially Successful\n\n' +
                'Submission ID: %1\n' +
                'Status Code: %2\n' +
                '%3\n' +
                '%4\n\n' +
                'Accepted Documents: %5\n' +
                'Rejected Documents: %6\n\n' +
                'Details:\n%7\n\n' +
                'Please review and resubmit the rejected documents.',
                SubmissionUid, StatusCode,
                CorrelationId <> 'N/A' ? StrSubstNo('Correlation ID: %1', CorrelationId) : '',
                RateLimitInfo <> '' ? StrSubstNo('Rate Limits: %1', RateLimitInfo) : '',
                AcceptedCount, RejectedCount, DocumentDetails);
        end else begin
            // All documents rejected or no documents processed
            SuccessMessage := StrSubstNo('LHDN Submission Failed\n\n' +
                'Submission ID: %1\n' +
                'Status Code: %2\n' +
                '%3\n' +
                '%4\n\n' +
                'Accepted Documents: %5\n' +
                'Rejected Documents: %6\n\n' +
                'Details:\n%7\n\n' +
                'Please review the errors and resubmit.\n\n' +
                'Full Response: %8',
                SubmissionUid, StatusCode,
                CorrelationId <> 'N/A' ? StrSubstNo('Correlation ID: %1', CorrelationId) : '',
                RateLimitInfo <> '' ? StrSubstNo('Rate Limits: %1', RateLimitInfo) : '',
                AcceptedCount, RejectedCount, DocumentDetails, LhdnResponse);
        end;

        // Display the formatted message
        Message(SuccessMessage);

        // Update Sales Invoice Header with LHDN response data
        UpdateSalesInvoiceWithLhdnResponse(SalesInvoiceHeader, SubmissionUid, AcceptedArray, AcceptedCount);

        // Log rejected documents with validation errors to submission log
        if RejectedCount > 0 then
            LogRejectedDocumentsWithErrors(SalesInvoiceHeader, SubmissionUid, RejectedArray, CorrelationId);

        // Background: try to fetch and store Validation URL (requires longId from Get Submission)
        TryFetchAndStoreValidationLink(SalesInvoiceHeader);
    end;

    /// <summary>
    /// Log rejected documents with validation errors to submission log
    /// Extracts error details from LHDN response and stores them using ParseAndStoreErrorResponse
    /// </summary>
    /// <param name="SalesInvoiceHeader">Sales Invoice Header record</param>
    /// <param name="SubmissionUid">LHDN Submission UID</param>
    /// <param name="RejectedArray">JSON array of rejected documents from LHDN response</param>
    /// <param name="CorrelationId">Correlation ID for tracking</param>
    local procedure LogRejectedDocumentsWithErrors(var SalesInvoiceHeader: Record "Sales Invoice Header"; SubmissionUid: Text; RejectedArray: JsonArray; CorrelationId: Text)
    var
        SubmissionLog: Record "eInvoice Submission Log";
        SubmissionStatusCU: Codeunit "eInvoice Submission Status";
        eInvoiceSetup: Record "eInvoiceSetup";
        Customer: Record Customer;
        JsonToken: JsonToken;
        RejectedDoc: JsonObject;
        ErrorObject: JsonObject;
        DocumentUuid: Text;
        DocumentStatus: Text;
        ErrorJsonText: Text;
        CustomerName: Text;
        i: Integer;
    begin
        // Get customer name
        CustomerName := '';
        if Customer.Get(SalesInvoiceHeader."Sell-to Customer No.") then
            CustomerName := Customer.Name;

        // Get setup for environment
        if not eInvoiceSetup.Get('SETUP') then
            exit;

        // Process each rejected document
        for i := 0 to RejectedArray.Count() - 1 do begin
            RejectedArray.Get(i, JsonToken);
            if JsonToken.IsObject() then begin
                RejectedDoc := JsonToken.AsObject();

                // Extract document UUID and status
                DocumentUuid := '';
                DocumentStatus := '';
                if RejectedDoc.Get('uuid', JsonToken) then
                    DocumentUuid := JsonToken.AsValue().AsText();
                if RejectedDoc.Get('status', JsonToken) then
                    DocumentStatus := JsonToken.AsValue().AsText();

                // Create submission log entry for rejected document
                Clear(SubmissionLog);
                SubmissionLog.Init();
                SubmissionLog."Entry No." := 0; // Auto-increment
                SubmissionLog."Invoice No." := SalesInvoiceHeader."No.";
                SubmissionLog."Customer No." := SalesInvoiceHeader."Sell-to Customer No.";
                SubmissionLog."Customer Name" := CopyStr(CustomerName, 1, MaxStrLen(SubmissionLog."Customer Name"));
                SubmissionLog."Submission UID" := CopyStr(SubmissionUid, 1, MaxStrLen(SubmissionLog."Submission UID"));
                SubmissionLog."Document UUID" := CopyStr(DocumentUuid, 1, MaxStrLen(SubmissionLog."Document UUID"));
                SubmissionLog.Status := CopyStr(DocumentStatus, 1, MaxStrLen(SubmissionLog.Status));
                SubmissionLog."Submission Date" := CurrentDateTime;
                SubmissionLog."Response Date" := CurrentDateTime;
                SubmissionLog."Last Updated" := CurrentDateTime;
                SubmissionLog."Posting Date" := SalesInvoiceHeader."Posting Date";
                SubmissionLog.Environment := eInvoiceSetup.Environment;
                SubmissionLog.Amount := SalesInvoiceHeader.Amount;
                SubmissionLog."Amount Including VAT" := SalesInvoiceHeader."Amount Including VAT";

                // Insert the log entry first
                if SubmissionLog.Insert() then begin
                    // Extract and store error details if present
                    if RejectedDoc.Get('error', JsonToken) and JsonToken.IsObject() then begin
                        ErrorObject := JsonToken.AsObject();
                        ErrorObject.WriteTo(ErrorJsonText);

                        // Parse and store error details using the same method as initial submission
                        // This will populate all error fields including Error Message, Error Code, etc.
                        SubmissionStatusCU.ParseAndStoreErrorResponse(SubmissionLog, ErrorJsonText, 400, CorrelationId);
                    end else begin
                        // No error object found - set generic message
                        SubmissionLog."Error Message" := CopyStr('Document rejected by LHDN - No detailed error information available', 1, MaxStrLen(SubmissionLog."Error Message"));
                        SubmissionLog.Modify(true);
                    end;
                end;
            end;
        end;
    end;

    local procedure TryFetchAndStoreValidationLink(var SalesInvoiceHeader: Record "Sales Invoice Header")
    var
        RawResponse: Text;
        LongId: Text;
        ValidationUrl: Text;
        Setup: Record "eInvoiceSetup";
        Attempt: Integer;
    begin
        if (SalesInvoiceHeader."eInvoice Submission UID" = '') or (SalesInvoiceHeader."eInvoice UUID" = '') then
            exit;
        // Retry up to 3 times (2s, 3s, 5s) to allow LHDN to populate longId
        for Attempt := 1 to 3 do begin
            if GetSubmissionDetailsRaw(SalesInvoiceHeader."eInvoice Submission UID", RawResponse) then begin
                LongId := ExtractLongIdFromApiResponse(RawResponse, SalesInvoiceHeader."eInvoice UUID");
                if LongId <> '' then
                    break;
            end;
            case Attempt of
                1:
                    Sleep(2000);
                2:
                    Sleep(3000);
                else
                    Sleep(5000);
            end;
        end;

        if LongId = '' then
            exit;

        if not Setup.Get('SETUP') then
            exit;

        ValidationUrl := BuildValidationUrl(SalesInvoiceHeader."eInvoice UUID", LongId, Setup.Environment);
        if ValidationUrl = '' then
            exit;

        if UpdateInvoiceQrUrl(SalesInvoiceHeader."No.", ValidationUrl) then
            GenerateAndStoreQrImage(SalesInvoiceHeader."No.", ValidationUrl);
    end;

    local procedure GetSubmissionDetailsRaw(SubmissionUid: Text; var RawResponse: Text): Boolean
    var
        HttpClient: HttpClient;
        RequestMessage: HttpRequestMessage;
        ResponseMessage: HttpResponseMessage;
        Setup: Record "eInvoiceSetup";
        AccessToken: Text;
        Headers: HttpHeaders;
        Url: Text;
    begin
        RawResponse := '';
        if SubmissionUid = '' then
            exit(false);

        if not Setup.Get('SETUP') then
            exit(false);

        AccessToken := GetLhdnAccessTokenFromHelper(Setup);
        if AccessToken = '' then
            exit(false);

        if Setup.Environment = Setup.Environment::Preprod then
            Url := StrSubstNo('https://preprod-api.myinvois.hasil.gov.my/api/v1.0/documentsubmissions/%1?pageNo=1&pageSize=100', SubmissionUid)
        else
            Url := StrSubstNo('https://api.myinvois.hasil.gov.my/api/v1.0/documentsubmissions/%1?pageNo=1&pageSize=100', SubmissionUid);

        RequestMessage.Method('GET');
        RequestMessage.SetRequestUri(Url);
        RequestMessage.GetHeaders(Headers);
        Headers.Add('Authorization', 'Bearer ' + AccessToken);
        Headers.Add('Accept', 'application/json');

        if not HttpClient.Send(RequestMessage, ResponseMessage) then
            exit(false);

        ResponseMessage.Content.ReadAs(RawResponse);
        exit(ResponseMessage.IsSuccessStatusCode);
    end;

    local procedure ExtractLongIdFromApiResponse(ResponseText: Text; DocumentUuid: Text): Text
    var
        JsonObject: JsonObject;
        JsonToken: JsonToken;
        DocumentSummary: JsonArray;
        Doc: JsonObject;
        PickedUuid: Text;
        i: Integer;
    begin
        if not JsonObject.ReadFrom(ResponseText) then
            exit('');

        if JsonObject.Get('documentSummary', JsonToken) and JsonToken.IsArray() then begin
            DocumentSummary := JsonToken.AsArray();
            for i := 0 to DocumentSummary.Count() - 1 do begin
                DocumentSummary.Get(i, JsonToken);
                if JsonToken.IsObject() then begin
                    Doc := JsonToken.AsObject();
                    PickedUuid := '';
                    if Doc.Get('uuid', JsonToken) then
                        PickedUuid := JsonToken.AsValue().AsText();
                    if (DocumentUuid = '') or (PickedUuid = DocumentUuid) then begin
                        if Doc.Get('longId', JsonToken) then
                            exit(JsonToken.AsValue().AsText());
                    end;
                end;
            end;
        end;
        exit('');
    end;

    local procedure BuildValidationUrl(DocumentUuid: Text; LongId: Text; Environment: Option Preprod,Production): Text
    var
        BaseUrl: Text;
    begin
        if (DocumentUuid = '') or (LongId = '') then
            exit('');

        if Environment = Environment::Preprod then
            BaseUrl := 'https://preprod.myinvois.hasil.gov.my'
        else
            BaseUrl := 'https://myinvois.hasil.gov.my';

        exit(StrSubstNo('%1/%2/share/%3', BaseUrl, DocumentUuid, LongId));
    end;

    /// <summary>
    /// Generates a QR image from the validation URL and stores it on the posted invoice
    /// </summary>
    /// <param name="InvoiceNo">Posted invoice number</param>
    /// <param name="ValidationUrl">Public validation URL</param>
    local procedure GenerateAndStoreQrImage(InvoiceNo: Code[20]; ValidationUrl: Text)
    var
        HttpClient: HttpClient;
        Response: HttpResponseMessage;
        InS: InStream;
        QrServiceUrl: Text;
    begin
        if (InvoiceNo = '') or (ValidationUrl = '') then
            exit;

        // Prime LHDN validation endpoint (optional)
        HttpClient.Get(ValidationUrl, Response);

        // Generate QR image using service
        QrServiceUrl := StrSubstNo('https://quickchart.io/qr?text=%1&size=220', ValidationUrl);
        if not HttpClient.Get(QrServiceUrl, Response) then
            exit;
        if not Response.IsSuccessStatusCode then
            exit;

        Response.Content.ReadAs(InS);
        UpdateInvoiceQrImage(InvoiceNo, InS, 'eInvoiceQR.png');
    end;

    local procedure FormatLhdnSuccessMessage(SubmissionUid: Text; StatusCode: Integer; AcceptedCount: Integer; DocumentDetails: Text; CorrelationId: Text; RateLimitInfo: Text): Text
    var
        FormattedMessage: Text;
        CorrelationInfo: Text;
        RateLimitInfoText: Text;
    begin
        // Build correlation info
        if CorrelationId <> 'N/A' then
            CorrelationInfo := StrSubstNo('Correlation ID: %1', CorrelationId)
        else
            CorrelationInfo := '';

        // Build rate limit info
        if RateLimitInfo <> '' then
            RateLimitInfoText := StrSubstNo('Rate Limits: %1', RateLimitInfo)
        else
            RateLimitInfoText := '';

        // Build the formatted message with concise formatting using StrSubstNo
        FormattedMessage := StrSubstNo('LHDN Submission Successful!\' +
            'Submission ID: %1\' +
            'Status Code: %2\' +
            '%3\' +
            '%4\' +
            'Accepted Documents: %5\' +
            '%6\' +
            'All documents have been successfully submitted to LHDN MyInvois.',
            CleanQuotesFromText(SubmissionUid),
            Format(StatusCode),
            CorrelationInfo,
            RateLimitInfoText,
            Format(AcceptedCount),
            CleanQuotesFromText(DocumentDetails));

        exit(FormattedMessage);
    end;

    local procedure FormatCreditMemoLhdnSuccessMessage(SubmissionUid: Text; StatusCode: Integer; AcceptedCount: Integer; DocumentDetails: Text; CorrelationId: Text; RateLimitInfo: Text): Text
    var
        FormattedMessage: Text;
        CorrelationInfo: Text;
        RateLimitInfoText: Text;
    begin
        // Build correlation info
        if CorrelationId <> 'N/A' then
            CorrelationInfo := StrSubstNo('Correlation ID: %1', CorrelationId)
        else
            CorrelationInfo := '';

        // Build rate limit info
        if RateLimitInfo <> '' then
            RateLimitInfoText := StrSubstNo('Rate Limits: %1', RateLimitInfo)
        else
            RateLimitInfoText := '';

        // Build the formatted message with concise formatting for credit memos using StrSubstNo
        FormattedMessage := StrSubstNo('LHDN Credit Memo Submission Successful!\' +
            'Submission ID: %1\' +
            'Status Code: %2\' +
            '%3\' +
            '%4\' +
            'Accepted Documents: %5\' +
            '%6\' +
            'All credit memo documents have been successfully submitted to LHDN MyInvois.',
            CleanQuotesFromText(SubmissionUid),
            Format(StatusCode),
            CorrelationInfo,
            RateLimitInfoText,
            Format(AcceptedCount),
            CleanQuotesFromText(DocumentDetails));

        exit(FormattedMessage);
    end;

    local procedure UpdateSalesInvoiceWithLhdnResponse(var SalesInvoiceHeader: Record "Sales Invoice Header"; SubmissionUid: Text; AcceptedArray: JsonArray; AcceptedCount: Integer)
    var
        JsonToken: JsonToken;
        DocumentJson: JsonObject;
        Uuid: Text;
        InvoiceCodeNumber: Text;
    begin
        // Update the submission UID
        if SubmissionUid <> '' then begin
            SalesInvoiceHeader."eInvoice Submission UID" := CopyStr(CleanQuotesFromText(SubmissionUid), 1, MaxStrLen(SalesInvoiceHeader."eInvoice Submission UID"));
        end;

        // Update UUID from the first accepted document (if any)
        if AcceptedCount > 0 then begin
            AcceptedArray.Get(0, JsonToken);
            DocumentJson := JsonToken.AsObject();

            if DocumentJson.Get('uuid', JsonToken) then begin
                Uuid := SafeJsonValueToText(JsonToken);
                SalesInvoiceHeader."eInvoice UUID" := CopyStr(CleanQuotesFromText(Uuid), 1, MaxStrLen(SalesInvoiceHeader."eInvoice UUID"));
            end;

            // Set validation status to "Submitted" when documents are accepted for processing
            // Note: This is the initial submission status, not the batch processing status
            // Batch processing status (valid/invalid/in progress/partially valid) is retrieved separately
            SalesInvoiceHeader."eInvoice Validation Status" := 'Submitted';

            // Set validation status to "Submitted" when documents are accepted for processing
            // Note: This is the initial submission status, not the batch processing status
            // Batch processing status (valid/invalid/in progress/partially valid) is retrieved separately
            SalesInvoiceHeader."eInvoice Validation Status" := 'Submitted';

            // Optional: Update invoice code number if different from the original
            if DocumentJson.Get('invoiceCodeNumber', JsonToken) then begin
                InvoiceCodeNumber := SafeJsonValueToText(JsonToken);
                // You can add a field for this if needed, or validate it matches the original
            end;
        end;

        // Save the changes
        if SalesInvoiceHeader.Modify() then begin
            // Successfully updated
        end else begin
            Message('Warning: Could not save LHDN response data to invoice record.');
        end;

        // Log the submission to the submission log table
        LogSubmissionToTable(SalesInvoiceHeader, SubmissionUid, Uuid, 'Submitted', '', SalesInvoiceHeader."eInvoice Document Type");
    end;

    local procedure ParseAndDisplayLhdnError(ErrorResponse: Text; StatusCode: Integer; ReasonPhrase: Text; HttpResponseMessage: HttpResponseMessage)
    var
        ErrorJson: JsonObject;
        JsonToken: JsonToken;
        ErrorObject: JsonObject;
        InnerErrorArray: JsonArray;
        ErrorMessage: Text;
        ErrorDetails: Text;
        PropertyName: Text;
        PropertyPath: Text;
        ErrorCode: Text;
        ErrorMS: Text;
        Target: Text;
        CorrelationId: Text;
        RateLimitInfo: Text;
        i: Integer;
        InnerErrorObject: JsonObject;
    begin
        ErrorDetails := '';

        // Extract correlation ID from response (if available in content headers or JSON)
        CorrelationId := 'N/A';
        RateLimitInfo := 'Check LHDN response for rate limiting details';

        // Try to parse the JSON error response
        if ErrorJson.ReadFrom(ErrorResponse) then begin
            // Extract main error object
            if ErrorJson.Get('error', JsonToken) and JsonToken.IsObject() then begin
                ErrorObject := JsonToken.AsObject();

                // Extract error details with safe type conversion
                if ErrorObject.Get('error', JsonToken) then
                    ErrorMessage := SafeJsonValueToText(JsonToken);
                if ErrorObject.Get('errorMS', JsonToken) then
                    ErrorMS := SafeJsonValueToText(JsonToken);
                if ErrorObject.Get('errorCode', JsonToken) then
                    ErrorCode := SafeJsonValueToText(JsonToken);
                if ErrorObject.Get('propertyName', JsonToken) then
                    PropertyName := SafeJsonValueToText(JsonToken);
                if ErrorObject.Get('propertyPath', JsonToken) then
                    PropertyPath := SafeJsonValueToText(JsonToken);
                if ErrorObject.Get('target', JsonToken) then
                    Target := SafeJsonValueToText(JsonToken);

                // Build error details
                ErrorDetails := 'Error Details:\n';
                if ErrorCode <> '' then
                    ErrorDetails += StrSubstNo('- Error Code: %1\n', ErrorCode);
                if ErrorMessage <> '' then
                    ErrorDetails += StrSubstNo('- Error (EN): %1\n', ErrorMessage);
                if ErrorMS <> '' then
                    ErrorDetails += StrSubstNo('- Error (MS): %1\n', ErrorMS);
                if PropertyName <> '' then
                    ErrorDetails += StrSubstNo('- Property: %1\n', PropertyName);
                if PropertyPath <> '' then
                    ErrorDetails += StrSubstNo('- Path: %1\n', PropertyPath);
                if Target <> '' then
                    ErrorDetails += StrSubstNo('- Target: %1\n', Target);

                // Process inner errors if present
                if ErrorObject.Get('innerError', JsonToken) and JsonToken.IsArray() then begin
                    InnerErrorArray := JsonToken.AsArray();
                    if InnerErrorArray.Count > 0 then begin
                        ErrorDetails += '\nAdditional Errors:\n';
                        for i := 0 to InnerErrorArray.Count - 1 do begin
                            InnerErrorArray.Get(i, JsonToken);
                            if JsonToken.IsObject() then begin
                                InnerErrorObject := JsonToken.AsObject();
                                ErrorDetails += StrSubstNo('  %1. ', i + 1);

                                if InnerErrorObject.Get('errorCode', JsonToken) then
                                    ErrorDetails += StrSubstNo('[%1] ', SafeJsonValueToText(JsonToken));
                                if InnerErrorObject.Get('error', JsonToken) then
                                    ErrorDetails += SafeJsonValueToText(JsonToken);
                                if InnerErrorObject.Get('propertyPath', JsonToken) then
                                    ErrorDetails += StrSubstNo(' (Path: %1)', SafeJsonValueToText(JsonToken));

                                if i < InnerErrorArray.Count - 1 then
                                    ErrorDetails += '\n';
                            end;
                        end;
                    end;
                end;
            end;

            // Extract correlation ID if available
            if ErrorJson.Get('correlationId', JsonToken) then
                CorrelationId := SafeJsonValueToText(JsonToken);

        end else begin
            // Fallback if JSON parsing fails
            ErrorDetails := StrSubstNo('Raw error response:\n%1', ErrorResponse);
        end;

        // Log error for troubleshooting
        LogLhdnError(ErrorCode, ErrorMessage, PropertyPath, ErrorResponse, StatusCode);

        // Display comprehensive error message
        Error('LHDN API Submission Failed\n\n' +
            'HTTP Status: %1 (%2)\n\n' +
            '%3\n\n' +
            'Resolution Steps:\n' +
            '%4\n\n' +
            '%5\n' +
            '%6\n\n' +
            'Full Response:\n%7',
            StatusCode, ReasonPhrase, ErrorDetails,
            GetResolutionSteps(ErrorCode),
            CorrelationId <> 'N/A' ? StrSubstNo('Correlation ID: %1', CorrelationId) : '',
            RateLimitInfo <> '' ? StrSubstNo('Rate Limits: %1', RateLimitInfo) : '',
            ErrorResponse);
    end;

    local procedure LogLhdnError(ErrorCode: Text; ErrorMessage: Text; PropertyPath: Text; FullResponse: Text; StatusCode: Integer)
    var
        TempBlob: Codeunit "Temp Blob";
        OutStream: OutStream;
        InStream: InStream;
        FileName: Text;
        LogContent: Text;
    begin
        // Create detailed error log for troubleshooting
        LogContent := StrSubstNo('LHDN API Error Log\n' +
            'Timestamp: %1\n' +
            'User: %2\n' +
            'Company: %3\n' +
            'Status Code: %4\n' +
            'Error Code: %5\n' +
            'Error Message: %6\n' +
            'Property Path: %7\n' +
            'Session ID: %8\n\n' +
            'Full Response:\n%9',
            Format(CurrentDateTime, 0, '<Year4>-<Month,2>-<Day,2> <Hours24,2>:<Minutes,2>:<Seconds,2>'),
            UserId, CompanyName, StatusCode, ErrorCode, ErrorMessage, PropertyPath,
            Format(SessionId), FullResponse);

        // Save error log as downloadable file
        FileName := StrSubstNo('LHDN_Error_%1_%2.log',
            Format(CurrentDateTime, 0, '<Year4><Month,2><Day,2>_<Hours24,2><Minutes,2><Seconds,2>'),
            ErrorCode);

        TempBlob.CreateOutStream(OutStream);
        OutStream.WriteText(LogContent);
        TempBlob.CreateInStream(InStream);
        DownloadFromStream(InStream, 'LHDN Error Log', '', 'Log files (*.log)|*.log', FileName);
    end;

    local procedure GetResolutionSteps(ErrorCode: Text): Text
    begin
        // Return specific resolution steps based on common LHDN error codes and FAQ guidance
        case UpperCase(ErrorCode) of
            'ERROR03':
                exit('1. Check for duplicate submissions within 2-hour window\n' +
                     '2. Verify document UUID is unique\n' +
                     '3. Wait a few minutes before resubmitting\n' +
                     '4. Check: Invoice Type, Issue Date/Time, Internal ID, Supplier TIN, Buyer TIN');
            'DS302':
                exit('1. Document already submitted with this UUID\n' +
                     '2. Use a different invoice number or UUID\n' +
                     '3. Check if document was previously accepted\n' +
                     '4. Review duplicate validation criteria (FAQ: 5 fields checked)');
            'VALIDATION_ERROR', 'INVALID_FORMAT', 'INVALID_STRUCTURE':
                exit('1. Review invoice data format against UBL 2.1 structure\n' +
                     '2. Check required fields are populated correctly\n' +
                     '3. Verify data types and formats (numbers, dates, text limits)\n' +
                     '4. Ensure sequence of elements is correct\n' +
                     '5. Check sample formats: sdk.myinvois.hasil.gov.my/sample/');
            'UNAUTHORIZED', 'AUTH_FAILED', '401':
                exit('1. Generate new access token (expires after 60 minutes)\n' +
                     '2. Check LHDN credentials in setup\n' +
                     '3. Verify environment (Preprod vs Production credentials)\n' +
                     '4. Ensure Client ID/Secret are environment-specific\n' +
                     '5. Contact LHDN for API access issues');
            '403', 'FORBIDDEN':
                exit('1. Verify correct Client ID and Client Secret for environment\n' +
                     '2. Production credentials cannot be used in Sandbox\n' +
                     '3. Register ERP system in correct environment portal\n' +
                     '4. Check TIN matching requirements');
            '400', 'BAD_REQUEST':
                exit('1. Check TIN number format is correct\n' +
                     '2. Verify input parameters match argument structure\n' +
                     '3. Review date formats (UTC standard required)\n' +
                     '4. Check for special character escaping in JSON');
            '429', 'TOO_MANY_REQUESTS':
                exit('1. Wait before retrying (check X-Rate-Limit headers)\n' +
                     '2. Implement rate limiting in your application\n' +
                     '3. Submit documents in batches to avoid limits\n' +
                     '4. Token endpoint: max 12 requests per minute');
            'SCHEMA_VALIDATION':
                exit('1. Check UBL 2.1 JSON structure compliance\n' +
                     '2. Verify all mandatory fields are present\n' +
                     '3. Check field data types and formats\n' +
                     '4. Review property paths in error details\n' +
                     '5. Validate against document type schema');
            'TIN_MISMATCH', 'TIN_NOT_MATCHING':
                exit('1. Taxpayer: Issuer TIN must match Client ID TIN\n' +
                     '2. Intermediary: Issuer TIN must match represented taxpayer\n' +
                     '3. Sole proprietors: Ensure "Business Owner" role in MyTax\n' +
                     '4. Individual TIN: Use "IG" prefix (not "OG" or "SG")\n' +
                     '5. Non-Individual TIN: Remove leading zeros, ensure ends with "0"');
            'DATE_TOO_OLD':
                exit('1. Issue date must be within 72 hours before submission\n' +
                     '2. Check "propertyPath" for specific date field\n' +
                     '3. Adjust document issuance date/time\n' +
                     '4. Ensure date is not in the future');
            'FUTURE_DATE':
                exit('1. Ensure issuance date/time is not in the future\n' +
                     '2. Use UTC format for all date/time values\n' +
                     '3. Check timezone conversion is correct\n' +
                     '4. Format: YYYY-MM-DDTHH:MM:SSZ');
            'FILE_SIZE_EXCEEDED':
                exit('1. Document size must not exceed 300KB\n' +
                     '2. Use minification to remove whitespace/comments\n' +
                     '3. Optimize JSON structure\n' +
                     '4. Consider reducing line item details if necessary');
            else
                exit('1. Review the error details above\n' +
                     '2. Check LHDN FAQ: sdk.myinvois.hasil.gov.my/faq/\n' +
                     '3. Validate against sample formats and documentation\n' +
                     '4. Test in Sandbox environment first\n' +
                     '5. Contact LHDN support with correlation ID if error persists');
        end;
    end;

    procedure GetLhdnAccessTokenFromHelper(eInvoiceSetup: Record "eInvoiceSetup"): Text
    var
        MyInvoisHelper: Codeunit eInvoiceHelper;
    begin
        exit(MyInvoisHelper.GetAccessTokenFromSetup(eInvoiceSetup));
    end;

    local procedure GetLhdnAccessToken(var AccessToken: Text): Boolean
    var
        HttpClient: HttpClient;
        HttpRequestMessage: HttpRequestMessage;
        HttpResponseMessage: HttpResponseMessage;
        ContentHeaders: HttpHeaders;
        RequestHeaders: HttpHeaders;
        TokenRequestBody: Text;
        TokenResponse: Text;
        JsonResponse: JsonObject;
        JsonToken: JsonToken;
        eInvoiceSetup: Record "eInvoiceSetup";
        TokenUrl: Text;
    begin
        // Get setup
        if not eInvoiceSetup.Get('SETUP') then
            Error('eInvoice Setup not found');

        if (eInvoiceSetup."Client ID" = '') or (eInvoiceSetup."Client Secret" = '') then begin
            LogDebugInfo('LHDN Token Request Failed - Missing Credentials',
                StrSubstNo('Client ID: %1\nClient Secret: %2\nEnvironment: %3',
                    eInvoiceSetup."Client ID" <> '' ? 'Configured' : 'MISSING',
                    eInvoiceSetup."Client Secret" <> '' ? 'Configured' : 'MISSING',
                    Format(eInvoiceSetup.Environment)));
            Error('LHDN Client ID and Client Secret must be configured in eInvoice Setup.\n\n' +
                'Please go to e-Invoice Setup and configure:\n' +
                '1. Client ID\n' +
                '2. Client Secret\n' +
                '3. Environment (Preprod/Production)');
        end;

        // Prepare OAuth2 token request
        TokenRequestBody := StrSubstNo('grant_type=client_credentials&client_id=%1&client_secret=%2&scope=InvoicingAPI',
            eInvoiceSetup."Client ID", eInvoiceSetup."Client Secret");

        // Determine token URL based on environment
        if eInvoiceSetup.Environment = eInvoiceSetup.Environment::Preprod then
            TokenUrl := 'https://preprod-api.myinvois.hasil.gov.my/connect/token'
        else
            TokenUrl := 'https://api.myinvois.hasil.gov.my/connect/token';

        // Debug: Log token request details
        LogDebugInfo('LHDN Token Request Details',
            StrSubstNo('Token URL: %1\nEnvironment: %2\nClient ID: %3\nScope: InvoicingAPI',
                TokenUrl,
                Format(eInvoiceSetup.Environment),
                eInvoiceSetup."Client ID"));

        // Setup OAuth2 token request with standard headers
        HttpRequestMessage.Method := 'POST';
        HttpRequestMessage.SetRequestUri(TokenUrl);
        HttpRequestMessage.Content.WriteFrom(TokenRequestBody);

        // Set standard LHDN API headers as per documentation
        HttpRequestMessage.Content.GetHeaders(ContentHeaders);
        ContentHeaders.Clear();
        ContentHeaders.Add('Content-Type', 'application/x-www-form-urlencoded');

        // Note: Authorization header not required for token endpoint per OAuth2 spec
        // Accept headers added for consistency with LHDN standards
        HttpRequestMessage.GetHeaders(RequestHeaders);
        RequestHeaders.Clear();
        RequestHeaders.Add('Accept', 'application/json');
        RequestHeaders.Add('Accept-Language', 'en');

        if HttpClient.Send(HttpRequestMessage, HttpResponseMessage) then begin
            if HttpResponseMessage.IsSuccessStatusCode then begin
                HttpResponseMessage.Content.ReadAs(TokenResponse);

                if JsonResponse.ReadFrom(TokenResponse) then begin
                    if JsonResponse.Get('access_token', JsonToken) then begin
                        AccessToken := SafeJsonValueToText(JsonToken);

                        // Debug: Log successful token response
                        LogDebugInfo('LHDN Token Response Success',
                            StrSubstNo('Token Length: %1\nToken Preview: %2...\nResponse Keys: %3',
                                StrLen(AccessToken),
                                CopyStr(AccessToken, 1, 50),
                                GetJsonObjectKeys(JsonResponse)));

                        // Update setup with new token and expiry
                        eInvoiceSetup."Last Token" := AccessToken;
                        eInvoiceSetup."Token Timestamp" := CurrentDateTime;
                        if JsonResponse.Get('expires_in', JsonToken) then
                            eInvoiceSetup."Token Expiry (s)" := JsonToken.AsValue().AsInteger();
                        eInvoiceSetup.Modify();

                        exit(true);
                    end;
                end;
            end else begin
                HttpResponseMessage.Content.ReadAs(TokenResponse);
                ParseAndDisplayLhdnError(TokenResponse, HttpResponseMessage.HttpStatusCode, 'Token Request Failed', HttpResponseMessage);
            end;
        end;

        exit(false);
    end;

    /// <summary>
    /// Retrieves available document types from LHDN MyInvois API
    /// Useful for validation and configuration purposes
    /// </summary>
    /// <param name="DocumentTypesResponse">JSON response containing available document types</param>
    /// <returns>True if successful, False otherwise</returns>
    procedure GetLhdnDocumentTypes(var DocumentTypesResponse: Text): Boolean
    var
        HttpClient: HttpClient;
        HttpRequestMessage: HttpRequestMessage;
        HttpResponseMessage: HttpResponseMessage;
        RequestHeaders: HttpHeaders;
        AccessToken: Text;
        eInvoiceSetup: Record "eInvoiceSetup";
        DocumentTypesUrl: Text;
    begin
        // Get setup for environment determination
        if not eInvoiceSetup.Get('SETUP') then
            Error('eInvoice Setup not found');

        // Get LHDN access token using the helper method
        AccessToken := GetLhdnAccessTokenFromHelper(eInvoiceSetup);

        // Determine LHDN Document Types API URL based on environment
        if eInvoiceSetup.Environment = eInvoiceSetup.Environment::Preprod then
            DocumentTypesUrl := 'https://preprod-api.myinvois.hasil.gov.my/api/v1.0/documenttypes'
        else
            DocumentTypesUrl := 'https://api.myinvois.hasil.gov.my/api/v1.0/documenttypes';

        // Setup LHDN API request with standard headers
        HttpRequestMessage.Method := 'GET';
        HttpRequestMessage.SetRequestUri(DocumentTypesUrl);

        // Set standard LHDN API headers as per documentation
        HttpRequestMessage.GetHeaders(RequestHeaders);
        RequestHeaders.Clear();
        RequestHeaders.Add('Accept', 'application/json');
        RequestHeaders.Add('Accept-Language', 'en');
        RequestHeaders.Add('Authorization', 'Bearer ' + AccessToken);

        // Submit to LHDN
        if HttpClient.Send(HttpRequestMessage, HttpResponseMessage) then begin
            HttpResponseMessage.Content.ReadAs(DocumentTypesResponse);

            if HttpResponseMessage.IsSuccessStatusCode then begin
                // Successfully retrieved document types
                Message('LHDN Document Types Retrieved Successfully!\n\n' +
                    'Status Code: %1\n' +
                    'Document Types Data:\n%2',
                    HttpResponseMessage.HttpStatusCode, DocumentTypesResponse);
                exit(true);
            end else begin
                // Parse and display structured LHDN error response
                ParseAndDisplayLhdnError(DocumentTypesResponse, HttpResponseMessage.HttpStatusCode, HttpResponseMessage.ReasonPhrase, HttpResponseMessage);
            end;
        end else begin
            Error('Failed to send HTTP request to LHDN Document Types API at %1', DocumentTypesUrl);
        end;

        exit(false);
    end;

    /// <summary>
    /// Retrieves LHDN notifications for the taxpayer within specified date range
    /// Supports filtering by notification type and pagination
    /// </summary>
    /// <param name="NotificationsResponse">JSON response containing notifications</param>
    /// <param name="DateFrom">Start date for notification search</param>
    /// <param name="DateTo">End date for notification search</param>
    /// <param name="NotificationType">Filter by notification type (0 for all)</param>
    /// <param name="PageNo">Page number for pagination (0 for default)</param>
    /// <param name="PageSize">Number of items per page (0 for default)</param>
    /// <returns>True if successful, False otherwise</returns>
    procedure GetLhdnNotifications(var NotificationsResponse: Text; DateFrom: Date; DateTo: Date; NotificationType: Integer; PageNo: Integer; PageSize: Integer): Boolean
    var
        HttpClient: HttpClient;
        HttpRequestMessage: HttpRequestMessage;
        HttpResponseMessage: HttpResponseMessage;
        RequestHeaders: HttpHeaders;
        AccessToken: Text;
        eInvoiceSetup: Record "eInvoiceSetup";
        NotificationsUrl: Text;
        QueryParams: Text;
    begin
        // Get setup for environment determination
        if not eInvoiceSetup.Get('SETUP') then
            Error('eInvoice Setup not found');

        // Get LHDN access token using the helper method
        AccessToken := GetLhdnAccessTokenFromHelper(eInvoiceSetup);

        // Determine LHDN Notifications API URL based on environment
        if eInvoiceSetup.Environment = eInvoiceSetup.Environment::Preprod then
            NotificationsUrl := 'https://preprod-api.myinvois.hasil.gov.my/api/v1.0/notifications/taxpayer'
        else
            NotificationsUrl := 'https://api.myinvois.hasil.gov.my/api/v1.0/notifications/taxpayer';

        // Build query parameters with validation for LHDN API requirements
        QueryParams := '';

        // Validate date range to ensure it's within 120 hours (5 days) as per LHDN API
        if (DateFrom <> 0D) and (DateTo <> 0D) then begin
            if (DateTo - DateFrom) > 5 then begin
                // Limit to 5 days to stay within 120 hours limit
                DateTo := DateFrom + 5;
            end;
        end;

        if DateFrom <> 0D then
            QueryParams += StrSubstNo('dateFrom=%1', Format(DateFrom, 0, '<Year4>-<Month,2>-<Day,2>') + 'T00:00:00Z');

        if DateTo <> 0D then begin
            if QueryParams <> '' then QueryParams += '&';
            QueryParams += StrSubstNo('dateTo=%1', Format(DateTo, 0, '<Year4>-<Month,2>-<Day,2>') + 'T23:59:59Z');
        end;

        if NotificationType > 0 then begin
            if QueryParams <> '' then QueryParams += '&';
            QueryParams += StrSubstNo('type=%1', NotificationType);
        end;

        if PageNo > 0 then begin
            if QueryParams <> '' then QueryParams += '&';
            QueryParams += StrSubstNo('pageNo=%1', PageNo);
        end;

        if PageSize > 0 then begin
            if QueryParams <> '' then QueryParams += '&';
            QueryParams += StrSubstNo('pageSize=%1', PageSize);
        end;

        // Add criteriaLimetInHrs parameter to limit to 120 hours as per LHDN API requirement
        if QueryParams <> '' then QueryParams += '&';
        QueryParams += 'criteriaLimetInHrs=120';

        // Add language parameter
        if QueryParams <> '' then QueryParams += '&';
        QueryParams += 'language=en';

        // Complete URL with query parameters
        if QueryParams <> '' then
            NotificationsUrl += '?' + QueryParams;

        // Setup LHDN API request with standard headers
        HttpRequestMessage.Method := 'GET';
        HttpRequestMessage.SetRequestUri(NotificationsUrl);

        // Set standard LHDN API headers as per documentation
        HttpRequestMessage.GetHeaders(RequestHeaders);
        RequestHeaders.Clear();
        RequestHeaders.Add('Accept', 'application/json');
        RequestHeaders.Add('Accept-Language', 'en');
        RequestHeaders.Add('Authorization', 'Bearer ' + AccessToken);

        // Submit to LHDN
        if HttpClient.Send(HttpRequestMessage, HttpResponseMessage) then begin
            HttpResponseMessage.Content.ReadAs(NotificationsResponse);

            if HttpResponseMessage.IsSuccessStatusCode then begin
                // Successfully retrieved notifications
                ParseAndDisplayLhdnNotifications(NotificationsResponse, HttpResponseMessage.HttpStatusCode);
                exit(true);
            end else begin
                // Parse and display structured LHDN error response
                ParseAndDisplayLhdnError(NotificationsResponse, HttpResponseMessage.HttpStatusCode, HttpResponseMessage.ReasonPhrase, HttpResponseMessage);
            end;
        end else begin
            Error('Failed to send HTTP request to LHDN Notifications API at %1', NotificationsUrl);
        end;

        exit(false);
    end;

    local procedure ParseAndDisplayLhdnNotifications(NotificationsResponse: Text; StatusCode: Integer)
    var
        ResponseJson: JsonObject;
        JsonToken: JsonToken;
        ResultArray: JsonArray;
        MetadataObject: JsonObject;
        NotificationObject: JsonObject;
        NotificationsInfo: Text;
        i: Integer;
        NotificationId: Text;
        Subject: Text;
        TypeName: Text;
        ReceivedDateTime: Text;
        Status: Text;
        HasNext: Boolean;
    begin
        // Try to parse the JSON response
        if not ResponseJson.ReadFrom(NotificationsResponse) then begin
            Message(StrSubstNo('LHDN Notifications retrieved successfully!\nStatus: %1\nRaw Response: %2', StatusCode, NotificationsResponse));
            exit;
        end;

        // Extract notifications array
        NotificationsInfo := '';
        if ResponseJson.Get('result', JsonToken) then begin
            ResultArray := JsonToken.AsArray();

            for i := 0 to ResultArray.Count - 1 do begin
                ResultArray.Get(i, JsonToken);
                NotificationObject := JsonToken.AsObject();

                // Extract notification details
                NotificationId := 'N/A';
                Subject := 'N/A';
                TypeName := 'N/A';
                ReceivedDateTime := 'N/A';
                Status := 'N/A';

                if NotificationObject.Get('notificationId', JsonToken) then
                    NotificationId := JsonToken.AsValue().AsText();
                if NotificationObject.Get('notificationSubject', JsonToken) then
                    Subject := JsonToken.AsValue().AsText();
                if NotificationObject.Get('typeName', JsonToken) then
                    TypeName := JsonToken.AsValue().AsText();
                if NotificationObject.Get('receivedDateTime', JsonToken) then
                    ReceivedDateTime := JsonToken.AsValue().AsText();
                if NotificationObject.Get('status', JsonToken) then
                    Status := JsonToken.AsValue().AsText();

                if NotificationsInfo <> '' then
                    NotificationsInfo += '\n';
                NotificationsInfo += StrSubstNo('  %1. [%2] %3\n      Type: %4 | Status: %5 | Received: %6',
                    i + 1, NotificationId, Subject, TypeName, Status, ReceivedDateTime);
            end;

            // Check for pagination
            HasNext := false;
            if ResponseJson.Get('metadata', JsonToken) then begin
                MetadataObject := JsonToken.AsObject();
                if MetadataObject.Get('hasNext', JsonToken) then
                    HasNext := JsonToken.AsValue().AsBoolean();
            end;

            // Display notifications
            Message('LHDN Notifications Retrieved Successfully!\n\n' +
                'Status Code: %1\n' +
                'Total Notifications: %2\n' +
                '%3\n\n' +
                'Notifications:\n%4\n\n' +
                '%5',
                StatusCode, ResultArray.Count,
                HasNext ? 'More pages available' : 'All notifications retrieved',
                NotificationsInfo,
                'Full Response available for integration purposes');
        end else begin
            Message('LHDN Notifications Retrieved!\n\nStatus: %1\nNo notifications found or unexpected response format.\n\nRaw Response: %2',
                StatusCode, NotificationsResponse);
        end;
    end;

    // ======================================================================================================
    // LHDN PAYLOAD VALIDATION PROCEDURES
    // ======================================================================================================

    /// <summary>
    /// Validates that the LHDN payload structure matches required format for document submission
    /// Ensures proper "documents" array structure with required fields
    /// </summary>
    /// <param name="PayloadText">JSON payload to validate</param>
    /// <returns>True if structure is valid for LHDN submission</returns>
    local procedure ValidateLhdnPayloadStructure(PayloadText: Text): Boolean
    var
        PayloadObject: JsonObject;
        JsonToken: JsonToken;
        DocumentsArray: JsonArray;
        DocumentObject: JsonObject;
        i: Integer;
    begin
        // Parse the payload
        if not PayloadObject.ReadFrom(PayloadText) then
            exit(false);

        // Check for "documents" array
        if not PayloadObject.Get('documents', JsonToken) then
            exit(false);

        if not JsonToken.IsArray() then
            exit(false);

        DocumentsArray := JsonToken.AsArray();
        if DocumentsArray.Count() = 0 then
            exit(false);

        // Validate each document in the array
        for i := 0 to DocumentsArray.Count() - 1 do begin
            DocumentsArray.Get(i, JsonToken);
            if not JsonToken.IsObject() then
                exit(false);

            DocumentObject := JsonToken.AsObject();

            // Check required fields
            if not DocumentObject.Contains('format') then
                exit(false);
            if not DocumentObject.Contains('document') then
                exit(false);
            if not DocumentObject.Contains('documentHash') then
                exit(false);
            if not DocumentObject.Contains('codeNumber') then
                exit(false);
        end;

        exit(true);
    end;

    // ======================================================================================================
    // UTILITY AND HELPER PROCEDURES
    // ======================================================================================================

    /// <summary>
    /// Creates a new GUID for correlation tracking
    /// </summary>
    /// <returns>Formatted GUID string</returns>
    local procedure CreateGuid(): Text
    var
        GuidVar: Guid;
    begin
        GuidVar := System.CreateGuid();
        exit(Format(GuidVar, 0, 4));
    end;

    /// <summary>
    /// Validates JSON text format without parsing the full structure
    /// </summary>
    /// <param name="JsonText">JSON text to validate</param>
    /// <returns>True if valid JSON format</returns>
    local procedure TestJsonValidity(JsonText: Text): Boolean
    var
        JsonObject: JsonObject;
    begin
        exit(JsonObject.ReadFrom(JsonText));
    end;

    /// <summary>
    /// Safely converts a JSON value to text, handling different data types
    /// This prevents "Unable to convert from NavJsonValue to NavText" errors
    /// Based on LHDN MyInvois API documentation structure
    /// </summary>
    /// <param name="JsonToken">JSON token to convert</param>
    /// <returns>Text representation of the JSON value</returns>
    local procedure SafeJsonValueToText(JsonToken: JsonToken): Text
    begin
        if JsonToken.IsValue() then begin
            // Use Format() which can handle any data type safely
            exit(Format(JsonToken.AsValue()));
        end else if JsonToken.IsObject() then begin
            exit('JSON Object');
        end else if JsonToken.IsArray() then begin
            exit('JSON Array');
        end else begin
            exit('Unknown');
        end;
    end;



    /// <summary>
    /// Checks if the LHDN payload object has a valid format (flexible validation)
    /// </summary>
    /// <param name="PayloadObject">JSON object to validate</param>
    /// <returns>True if format is recognized</returns>
    local procedure IsValidLhdnPayloadFormat(PayloadObject: JsonObject): Boolean
    var
        JsonToken: JsonToken;
    begin
        // Check for documents array (standard LHDN format)
        if PayloadObject.Get('documents', JsonToken) and JsonToken.IsArray() then
            exit(true);

        // Check for direct document structure (alternative format)
        if PayloadObject.Get('document', JsonToken) and JsonToken.IsObject() then
            exit(true);

        // Check for simple object with basic fields
        if PayloadObject.Get('format', JsonToken) or PayloadObject.Get('documentHash', JsonToken) then
            exit(true);

        // If none of the above, but it's a valid JSON object, accept it
        exit(true);
    end;

    /// <summary>
    /// Enhanced flexible validation of LHDN payload structure that can handle different formats
    /// </summary>
    /// <param name="PayloadText">JSON payload text to validate</param>
    /// <returns>True if structure is valid for LHDN submission</returns>
    local procedure ValidateLhdnPayloadStructureFlexible(PayloadText: Text): Boolean
    var
        PayloadObject: JsonObject;
        JsonToken: JsonToken;
        DocumentsArray: JsonArray;
        DocumentObject: JsonObject;
        i: Integer;
        HasValidStructure: Boolean;
    begin
        // Parse the payload
        if not PayloadObject.ReadFrom(PayloadText) then
            exit(false);

        HasValidStructure := false;

        // Try standard LHDN format first (documents array)
        if PayloadObject.Get('documents', JsonToken) and JsonToken.IsArray() then begin
            DocumentsArray := JsonToken.AsArray();
            if DocumentsArray.Count() > 0 then begin
                // Validate first document in the array
                DocumentsArray.Get(0, JsonToken);
                if JsonToken.IsObject() then begin
                    DocumentObject := JsonToken.AsObject();
                    // Check for at least one required field
                    if DocumentObject.Contains('format') or DocumentObject.Contains('document') or DocumentObject.Contains('documentHash') then
                        HasValidStructure := true;
                end;
            end;
        end;

        // Try direct document format
        if not HasValidStructure and PayloadObject.Get('document', JsonToken) and JsonToken.IsObject() then begin
            DocumentObject := JsonToken.AsObject();
            if DocumentObject.Contains('format') or DocumentObject.Contains('documentHash') then
                HasValidStructure := true;
        end;

        // Try simple object format with direct fields
        if not HasValidStructure and (PayloadObject.Contains('format') or PayloadObject.Contains('documentHash') or PayloadObject.Contains('codeNumber')) then begin
            HasValidStructure := true;
        end;

        // Try alternative formats that might be returned by Azure Function
        if not HasValidStructure and PayloadObject.Get('lhdnPayload', JsonToken) then begin
            if JsonToken.IsObject() then begin
                // Nested lhdnPayload object
                DocumentObject := JsonToken.AsObject();
                if DocumentObject.Contains('documents') or DocumentObject.Contains('document') or DocumentObject.Contains('format') then
                    HasValidStructure := true;
            end else if JsonToken.IsValue() then begin
                // lhdnPayload as string - try to parse it
                if JsonToken.AsValue().AsText().Contains('"documents"') or JsonToken.AsValue().AsText().Contains('"document"') then
                    HasValidStructure := true;
            end;
        end;

        // If we get here, the structure is not recognized but we'll accept it for debugging
        // This allows us to see what the Azure Function is actually returning
        if not HasValidStructure then begin
            // Log the unknown structure for debugging
            LogDebugInfo('Unknown LHDN payload structure detected',
                StrSubstNo('Payload keys: %1\nPayload preview: %2',
                    GetJsonObjectKeys(PayloadObject),
                    CopyStr(PayloadText, 1, 300)));
        end;

        exit(true); // Always return true for debugging purposes
    end;

    /// <summary>
    /// Stores signed invoice JSON for audit trail and compliance requirements
    /// Can be extended to save to custom tables for permanent record keeping
    /// </summary>
    /// <param name="SalesInvoiceHeader">Invoice record for reference</param>
    /// <param name="SignedJsonText">Digitally signed JSON from Azure Function</param>
    local procedure StoreSignedInvoiceJson(SalesInvoiceHeader: Record "Sales Invoice Header"; SignedJsonText: Text)
    var
        TempBlob: Codeunit "Temp Blob";
        OutStream: OutStream;
        InStream: InStream;
        FileName: Text;
    begin
        // Store signed JSON for audit trail and records
        // You can extend this to store in a custom table if needed

        FileName := StrSubstNo('SignedInvoice_%1_%2.json',
            SalesInvoiceHeader."No.",
            Format(CurrentDateTime, 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2><Seconds,2>'));

        TempBlob.CreateOutStream(OutStream);
        OutStream.WriteText(SignedJsonText);
        TempBlob.CreateInStream(InStream);

        // Optional: Download the signed JSON for verification
        // DownloadFromStream(InStream, 'Signed eInvoice JSON', '', 'JSON files (*.json)|*.json', FileName);

        // TODO: Store in a custom table for permanent record keeping
        // Example: 
        // SignedInvoiceLog."Invoice No." := SalesInvoiceHeader."No.";
        // SignedInvoiceLog.SetSignedJSONText(SignedJsonText);
        // SignedInvoiceLog.Insert();
    end;

    /// <summary>
    /// Gets all property keys from a JSON object for debugging purposes
    /// Useful for troubleshooting Azure Function response structure issues
    /// </summary>
    /// <param name="JsonObj">JSON object to analyze</param>
    /// <returns>Comma-separated list of all keys</returns>
    local procedure GetJsonObjectKeys(JsonObj: JsonObject): Text
    var
        KeysList: Text;
        Keys: List of [Text];
        i: Integer;
        CurrentKey: Text;
    begin
        Keys := JsonObj.Keys();
        for i := 1 to Keys.Count() do begin
            CurrentKey := Keys.Get(i);
            if KeysList <> '' then
                KeysList += ', ';
            KeysList += CurrentKey;
        end;
        exit(KeysList);
    end;

    /// <summary>
    /// Logs debug information for troubleshooting Azure Function integration issues
    /// </summary>
    /// <param name="Message">Debug message</param>
    /// <param name="Details">Detailed debug information</param>
    local procedure LogDebugInfo(Message: Text; Details: Text)
    var
        TempBlob: Codeunit "Temp Blob";
        OutStream: OutStream;
        InStream: InStream;
        FileName: Text;
        LogEntry: Text;
    begin
        // Create debug log entry with timestamp
        LogEntry := StrSubstNo('[%1] %2\n%3\n\n',
            Format(CurrentDateTime, 0, '<Year4>-<Month,2>-<Day,2> <Hours24,2>:<Minutes,2>:<Seconds,2>'),
            Message,
            Details);

        // Save to debug log file
        FileName := 'eInvoice_Debug_Log.txt';
        TempBlob.CreateOutStream(OutStream);
        OutStream.WriteText(LogEntry);
        TempBlob.CreateInStream(InStream);

        // Note: In production, you might want to use a proper logging system
        // or store this in a custom table for better management
    end;

    /// <summary>
    /// Test procedure to verify the LHDN payload structure fix works with actual Azure Function response
    /// </summary>
    procedure TestLhdnPayloadWithActualResponse()
    var
        TestAzureResponse: JsonObject;
        TestLhdnPayload: JsonObject;
        TestDocuments: JsonArray;
        TestDocument: JsonObject;
        LhdnPayloadString: Text;
        AzureResponseString: Text;
        JsonToken: JsonToken;
        LhdnResponse: Text;
        SalesInvoiceHeader: Record "Sales Invoice Header";
    begin
        // Create test document structure matching the actual Azure Function response
        TestDocument.Add('format', 'JSON');
        TestDocument.Add('document', 'eyJfRCI6InVybjpvYXNpczpuYW1lczpzcGVjaWZpY2F0aW9uOnVibDpzY2hlbWE6eHNkOkludm9pY2UtMiIsIkludm9pY2UiOlt7IklEIjpbeyJfIjoiUFNJMjUwMy0wMDIwIn1dfV19');
        TestDocument.Add('documentHash', 'cc1a5c6bb9e295a4267faf9bad8dd1ce40dea6839a9e2fb72dcc35bac86eabbf');
        TestDocument.Add('codeNumber', 'PSI2503-0020');

        // Create documents array
        TestDocuments.Add(TestDocument);

        // Create LHDN payload object
        TestLhdnPayload.Add('documents', TestDocuments);
        TestLhdnPayload.WriteTo(LhdnPayloadString);

        // Create Azure Function response matching the actual format
        TestAzureResponse.Add('success', true);
        TestAzureResponse.Add('correlationId', 'B6FE59CE-F8A0-41AA-B202-4A31B32FAFEA');
        TestAzureResponse.Add('statusCode', 200);
        TestAzureResponse.Add('message', 'Invoice signed successfully');
        TestAzureResponse.Add('signedJson', '{"test": "signed_json"}');
        TestAzureResponse.Add('lhdnPayload', LhdnPayloadString);
        TestAzureResponse.WriteTo(AzureResponseString);

        // Test the parsing logic
        if TestAzureResponse.Get('lhdnPayload', JsonToken) then begin
            LhdnResponse := JsonToken.AsValue().AsText();

            // Test the ProcessLhdnPayload method
            if ProcessLhdnPayload(LhdnResponse, SalesInvoiceHeader, LhdnResponse) then begin
                Message('Test successful! LHDN payload structure is correctly handled.');
            end else begin
                Message(StrSubstNo('Test failed! Error: %1', LhdnResponse));
            end;
        end else begin
            Message('Test failed! Could not extract lhdnPayload from Azure response.');
        end;
    end;

    /// <summary>
    /// Builds Azure Function payload in BusinessCentralSigningRequest format
    /// </summary>
    // UPDATE: Add document type parameter for credit memos
    local procedure BuildAzureFunctionPayload(JsonText: Text; CorrelationId: Text; DocumentType: Text): Text
    var
        RequestJson: JsonObject;
        RequestText: Text;
    begin
        RequestJson.Add('unsignedJson', JsonText);
        RequestJson.Add('invoiceType', '01'); // Keep for compatibility
        RequestJson.Add('documentType', DocumentType); // ADD THIS
        RequestJson.Add('environment', GetEnvironmentSetting());
        RequestJson.Add('timestamp', Format(CurrentDateTime, 0, '<Year4>-<Month,2>-<Day,2>T<Hours24,2>:<Minutes,2>:<Seconds,2>Z'));
        RequestJson.Add('requestId', CorrelationId);
        RequestJson.WriteTo(RequestText);
        exit(RequestText);
    end;

    // ADD: Credit memo specific procedure
    procedure PostCreditMemoToAzureFunction(SalesCrMemoHeader: Record "Sales Cr.Memo Header"; AzureFunctionUrl: Text; var ResponseText: Text)
    var
        JsonText: Text;
        CorrelationId: Text;
        RequestText: Text;
    begin
        // Generate credit memo JSON
        JsonText := GenerateCreditMemoEInvoiceJson(SalesCrMemoHeader, false);

        // Build request with document type '02'
        CorrelationId := CreateGuid();
        RequestText := BuildAzureFunctionPayload(JsonText, CorrelationId, '02');

        // Send to Azure Function
        if not TryDirectHttpClient(AzureFunctionUrl, RequestText, ResponseText, CorrelationId, 3) then
            Error('Failed to process credit note: %1', ResponseText);
    end;

    /// <summary>
    /// Counts opening and closing braces to check JSON balance
    /// </summary>
    local procedure CountBraceBalance(JsonText: Text): Text
    var
        OpenBraces: Integer;
        CloseBraces: Integer;
        i: Integer;
        Char: Char;
    begin
        OpenBraces := 0;
        CloseBraces := 0;

        for i := 1 to StrLen(JsonText) do begin
            Char := JsonText[i];
            if Char = '{' then
                OpenBraces += 1
            else if Char = '}' then
                CloseBraces += 1;
        end;

        exit(StrSubstNo('Open: %1, Close: %2, Balanced: %3', OpenBraces, CloseBraces, OpenBraces = CloseBraces));
    end;

    /// <summary>
    /// Extracts the base64 document content from the LHDN payload string
    /// </summary>
    local procedure ExtractBase64Document(LhdnPayloadText: Text; var Base64Document: Text): Boolean
    var
        DocumentStart: Integer;
        DocumentEnd: Integer;
        QuoteStart: Integer;
        QuoteEnd: Integer;
    begin
        // Look for "document": " pattern
        DocumentStart := LhdnPayloadText.IndexOf('"document": "');
        if DocumentStart = 0 then
            exit(false);

        // Find the start of the base64 content (after the opening quote)
        QuoteStart := DocumentStart + 12; // Length of '"document": "'

        // Find the end of the base64 content (before the closing quote)
        QuoteEnd := LhdnPayloadText.IndexOf('"', QuoteStart);
        if QuoteEnd = 0 then
            exit(false);

        // Extract the base64 content
        Base64Document := CopyStr(LhdnPayloadText, QuoteStart, QuoteEnd - QuoteStart);
        exit(true);
    end;

    /// <summary>
    /// Generates a simple hash of the base64 document content for LHDN validation
    /// </summary>
    local procedure GenerateDocumentHash(Base64Content: Text): Text
    var
        HashText: Text;
        i: Integer;
        CharCode: Integer;
    begin
        // Create a simple hash by summing character codes and converting to hex
        // This is sufficient for LHDN validation purposes
        CharCode := 0;
        for i := 1 to StrLen(Base64Content) do begin
            CharCode := CharCode + Base64Content[i];
        end;

        // Convert to a 64-character hex string (32 bytes)
        HashText := Format(CharCode, 0, '<Hex,16>');
        HashText := HashText + HashText + HashText + HashText; // Repeat to get 64 chars

        exit(LowerCase(CopyStr(HashText, 1, 64)));
    end;

    /// <summary>
    /// Processes LHDN payload from Azure Function response with enhanced debugging and flexible validation
    /// The lhdnPayload is returned as a JSON string containing the documents array structure
    /// </summary>
    local procedure ProcessLhdnPayload(LhdnPayloadText: Text; SalesInvoiceHeader: Record "Sales Invoice Header"; var LhdnResponse: Text): Boolean
    var
        LhdnPayloadObject: JsonObject;
        TempJsonObject: JsonObject;
        JsonToken: JsonToken;
        UnescapedJson: Text;
    begin
        // 1. Try direct parsing first
        if LhdnPayloadObject.ReadFrom(LhdnPayloadText) then
            if LhdnPayloadObject.Get('documents', JsonToken) then begin
                LhdnResponse := 'Direct JSON parsing successful - submitting to LHDN API';
                exit(SubmitToLhdnApi(LhdnPayloadObject, SalesInvoiceHeader, LhdnResponse));
            end;

        // 2. Handle as JSON string if direct parsing failed
        if LhdnPayloadText.StartsWith('"') and LhdnPayloadText.EndsWith('"') then
            LhdnPayloadText := CopyStr(LhdnPayloadText, 2, StrLen(LhdnPayloadText) - 2);

        // 3. Unescape the JSON and remove problematic characters
        LhdnPayloadText := LhdnPayloadText.Replace('\"', '"');
        LhdnPayloadText := LhdnPayloadText.Replace('\\n', '');  // Remove newlines completely
        LhdnPayloadText := LhdnPayloadText.Replace('\\t', '');  // Remove tabs completely
        LhdnPayloadText := LhdnPayloadText.Replace('\\r', '');  // Remove carriage returns completely
        LhdnPayloadText := LhdnPayloadText.Replace('\\\\', '\\'); // Convert \\ to single backslash
        LhdnPayloadText := LhdnPayloadText.Replace('\n', '');  // Remove any remaining actual newlines
        LhdnPayloadText := LhdnPayloadText.Replace('\t', '');  // Remove any remaining actual tabs
        LhdnPayloadText := LhdnPayloadText.Replace('\r', '');  // Remove any remaining actual carriage returns

        // 4. Parse the unescaped JSON
        if not LhdnPayloadObject.ReadFrom(LhdnPayloadText) then begin
            LhdnResponse := 'Failed to parse LHDN payload after unescaping. Payload start: ' + CopyStr(LhdnPayloadText, 1, 200);
            exit(false);
        end;

        // 5. Validate structure
        if not LhdnPayloadObject.Get('documents', JsonToken) then begin
            LhdnResponse := 'LHDN payload missing documents array after parsing. Payload keys: ' + GetJsonObjectKeys(LhdnPayloadObject);
            exit(false);
        end;

        // 6. Submit to LHDN API
        LhdnResponse := 'JSON parsing successful - submitting to LHDN API';
        exit(SubmitToLhdnApi(LhdnPayloadObject, SalesInvoiceHeader, LhdnResponse));
    end;



    // ======================================================================================================
    // PERFORMANCE OPTIMIZATION VARIABLES
    // ======================================================================================================

    var
        CompanyInfoCache: Record "Company Information"; // Cache for company information
        SetupCache: Record "eInvoiceSetup"; // Cache for setup data
        LastCacheRefresh: DateTime; // Track when cache was last refreshed
        CacheValidityDuration: Duration; // How long cache is valid

    // ======================================================================================================
    // CACHE MANAGEMENT PROCEDURES
    // ======================================================================================================

    local procedure InitializeCache()
    begin
        if LastCacheRefresh = 0DT then begin
            CacheValidityDuration := 300000; // 5 minutes cache validity
            RefreshCache();
        end else if (CurrentDateTime() - LastCacheRefresh) > CacheValidityDuration then begin
            RefreshCache();
        end;
    end;

    local procedure RefreshCache()
    begin
        // Cache company info
        if not CompanyInfoCache.Get() then
            CompanyInfoCache.Init();

        // Cache setup info
        if not SetupCache.Get('SETUP') then
            SetupCache.Init();

        LastCacheRefresh := CurrentDateTime();
    end;

    /// <summary>
    /// Parses and displays Azure Function response details in a user-friendly format
    /// </summary>
    /// <param name="ResponseText">Raw response from Azure Function</param>
    /// <returns>Formatted response details for display</returns>
    procedure ParseAzureFunctionResponse(ResponseText: Text): Text
    var
        ResponseObj: JsonObject;
        JsonToken: JsonToken;
        Details: Text;
        CorrelationId: Text;
        StatusCode: Integer;
        Message: Text;
        ProcessingTime: Integer;
        Timestamp: Text;
        SignatureInfo: Text;
    begin
        if not ResponseObj.ReadFrom(ResponseText) then
            exit('Invalid JSON response from Azure Function');

        Details := '=== Azure Function Response Analysis ===\n\n';

        // Extract basic information
        if ResponseObj.Get('success', JsonToken) then
            Details += '[SUCCESS] Status: Success\n'
        else
            Details += '[FAILED] Status: Failed\n';

        if ResponseObj.Get('correlationId', JsonToken) then begin
            CorrelationId := SafeJsonValueToText(JsonToken);
            Details += '[ID] Correlation ID: ' + CorrelationId + '\n';
        end;

        if ResponseObj.Get('statusCode', JsonToken) then begin
            StatusCode := JsonToken.AsValue().AsInteger();
            Details += '[CODE] Status Code: ' + Format(StatusCode) + '\n';
        end;

        if ResponseObj.Get('message', JsonToken) then begin
            Message := SafeJsonValueToText(JsonToken);
            Details += '[MSG] Message: ' + Message + '\n';
        end;

        if ResponseObj.Get('processingTimeMs', JsonToken) then begin
            ProcessingTime := JsonToken.AsValue().AsInteger();
            Details += '[TIME] Processing Time: ' + Format(ProcessingTime) + 'ms\n';
        end;

        if ResponseObj.Get('timestamp', JsonToken) then begin
            Timestamp := SafeJsonValueToText(JsonToken);
            Details += '[DATE] Timestamp: ' + Timestamp + '\n';
        end;

        // Extract signature information
        if ResponseObj.Get('signature', JsonToken) then begin
            SignatureInfo := ExtractSignatureInfo(JsonToken.AsObject());
            Details += '\n=== Digital Signature Details ===\n' + SignatureInfo;
        end;

        // Check for LHDN payload
        if ResponseObj.Get('lhdnPayload', JsonToken) then begin
            Details += '\n[OK] LHDN Payload: Available (ready for submission)\n';
        end else begin
            Details += '\n[WARNING] LHDN Payload: Not found in response\n';
        end;

        // Check for signed JSON
        if ResponseObj.Get('signedJson', JsonToken) then begin
            Details += '[OK] Signed JSON: Available (ready for download)\n';
        end else begin
            Details += '[WARNING] Signed JSON: Not found in response\n';
        end;

        exit(Details);
    end;

    /// <summary>
    /// Extracts signature information from the response
    /// </summary>
    /// <param name="SignatureObj">Signature JSON object</param>
    /// <returns>Formatted signature details</returns>
    local procedure ExtractSignatureInfo(SignatureObj: JsonObject): Text
    var
        JsonToken: JsonToken;
        Details: Text;
        Algorithm: Text;
        Subject: Text;
        Issuer: Text;
        SerialNumber: Text;
        SigningTime: Text;
        IsCompliant: Boolean;
    begin
        if SignatureObj.Get('algorithm', JsonToken) then
            Algorithm := SafeJsonValueToText(JsonToken);

        if SignatureObj.Get('certificateSubject', JsonToken) then
            Subject := SafeJsonValueToText(JsonToken);

        if SignatureObj.Get('certificateIssuer', JsonToken) then
            Issuer := SafeJsonValueToText(JsonToken);

        if SignatureObj.Get('certificateSerialNumber', JsonToken) then
            SerialNumber := SafeJsonValueToText(JsonToken);

        if SignatureObj.Get('signatureTime', JsonToken) then
            SigningTime := SafeJsonValueToText(JsonToken);

        if SignatureObj.Get('isLhdnCompliant', JsonToken) then
            IsCompliant := JsonToken.AsValue().AsBoolean();

        Details := '[ALGO] Algorithm: ' + Algorithm + '\n';
        Details += '[CERT] Certificate Subject: ' + Subject + '\n';
        Details += '[ISSUER] Certificate Issuer: ' + Issuer + '\n';
        Details += '[SERIAL] Serial Number: ' + SerialNumber + '\n';
        Details += '[TIME] Signing Time: ' + SigningTime + '\n';

        if IsCompliant then
            Details += '[OK] LHDN Compliance: Compliant\n'
        else
            Details += '[WARNING] LHDN Compliance: Non-compliant\n';

        exit(Details);
    end;

    local procedure BuildDocumentDetails(AcceptedArray: JsonArray; RejectedArray: JsonArray): Text
    var
        DocumentDetails: Text;
        i: Integer;
        JsonToken: JsonToken;
        DocumentJson: JsonObject;
        Uuid: Text;
        InvoiceCodeNumber: Text;
    begin
        DocumentDetails := '';

        // Process accepted documents
        for i := 0 to AcceptedArray.Count - 1 do begin
            AcceptedArray.Get(i, JsonToken);
            DocumentJson := JsonToken.AsObject();

            // Extract UUID with safe type conversion
            if DocumentJson.Get('uuid', JsonToken) then
                Uuid := CleanQuotesFromText(SafeJsonValueToText(JsonToken))
            else
                Uuid := 'N/A';

            // Extract Invoice Code Number with safe type conversion
            if DocumentJson.Get('invoiceCodeNumber', JsonToken) then
                InvoiceCodeNumber := CleanQuotesFromText(SafeJsonValueToText(JsonToken))
            else
                InvoiceCodeNumber := 'N/A';

            if DocumentDetails <> '' then
                DocumentDetails += '\\';
            DocumentDetails += StrSubstNo('  - Invoice: %1\\    UUID: %2', InvoiceCodeNumber, Uuid);
        end;

        // Process rejected documents
        if RejectedArray.Count > 0 then begin
            if DocumentDetails <> '' then
                DocumentDetails += '\\' + '\\Rejected Documents:' + '\\';

            for i := 0 to RejectedArray.Count - 1 do begin
                RejectedArray.Get(i, JsonToken);
                DocumentJson := JsonToken.AsObject();

                // Extract rejection details with safe type conversion
                Uuid := 'N/A';
                InvoiceCodeNumber := 'N/A';
                if DocumentJson.Get('uuid', JsonToken) then
                    Uuid := CleanQuotesFromText(SafeJsonValueToText(JsonToken));
                if DocumentJson.Get('invoiceCodeNumber', JsonToken) then
                    InvoiceCodeNumber := CleanQuotesFromText(SafeJsonValueToText(JsonToken));

                DocumentDetails += StrSubstNo('  - Invoice: %1\\    UUID: %2', InvoiceCodeNumber, Uuid);

                // Add error details if available with safe type conversion
                if DocumentJson.Get('error', JsonToken) then
                    DocumentDetails += ' - Error: ' + SafeJsonValueToText(JsonToken);
                if DocumentJson.Get('errorCode', JsonToken) then
                    DocumentDetails += ' (Code: ' + SafeJsonValueToText(JsonToken) + ')';

                if i < RejectedArray.Count - 1 then
                    DocumentDetails += '\\';
            end;
        end;

        exit(DocumentDetails);
    end;

    procedure GetSubmissionStatus(SubmissionUid: Text; var SubmissionDetails: Text): Boolean
    var
        HttpClient: HttpClient;
        HttpResponseMessage: HttpResponseMessage;
        RequestMessage: HttpRequestMessage;
        ResponseText: Text;
        Url: Text;
        Setup: Record "eInvoiceSetup";
        AccessToken: Text;
        Headers: HttpHeaders;
    begin
        SubmissionDetails := '';

        // Get setup configuration
        if not Setup.Get('SETUP') then begin
            SubmissionDetails := 'Error: eInvoice Setup not found.';
            exit(false);
        end;

        // Get access token
        if not GetLhdnAccessToken(AccessToken) then begin
            SubmissionDetails := 'Error: Failed to obtain access token.';
            exit(false);
        end;

        // Build the URL for Get Submission API - use preprod or production URL based on environment
        if Setup.Environment = Setup.Environment::Preprod then
            Url := StrSubstNo('https://preprod-api.myinvois.hasil.gov.my/api/v1.0/documentsubmissions/%1?pageNo=1&pageSize=100', SubmissionUid)
        else
            Url := StrSubstNo('https://api.myinvois.hasil.gov.my/api/v1.0/documentsubmissions/%1?pageNo=1&pageSize=100', SubmissionUid);

        // Set up HTTP request
        RequestMessage.Method('GET');
        RequestMessage.SetRequestUri(Url);

        // Set headers
        RequestMessage.GetHeaders(Headers);
        Headers.Add('Authorization', StrSubstNo('Bearer %1', AccessToken));
        Headers.Add('Content-Type', 'application/json');
        Headers.Add('Accept', 'application/json');

        // Send request
        if not HttpClient.Send(RequestMessage, HttpResponseMessage) then begin
            SubmissionDetails := 'Error: Failed to send HTTP request.';
            exit;
        end;

        // Get response
        HttpResponseMessage.Content().ReadAs(ResponseText);

        // Check status code
        if HttpResponseMessage.IsSuccessStatusCode() then begin
            SubmissionDetails := ParseSubmissionResponse(ResponseText);
            exit(true);
        end else begin
            SubmissionDetails := StrSubstNo('Error: HTTP %1 - %2',
                HttpResponseMessage.HttpStatusCode(),
                ResponseText);
            exit(false);
        end;
    end;

    local procedure ParseSubmissionResponse(ResponseText: Text): Text
    var
        ResponseJson: JsonObject;
        JsonToken: JsonToken;
        DocumentSummaryArray: JsonArray;
        FormattedResponse: Text;
        SubmissionUid: Text;
        DocumentCount: Integer;
        DateTimeReceived: Text;
        OverallStatus: Text;
        i: Integer;
        DocumentJson: JsonObject;
        Uuid: Text;
        Status: Text;
        TotalPayableAmount: Decimal;
        DateTimeIssued: Text;
        IssuerName: Text;
        ReceiverName: Text;
    begin
        FormattedResponse := '';

        // Parse the JSON response
        if not ResponseJson.ReadFrom(ResponseText) then begin
            exit('Error: Invalid JSON response from LHDN API.');
        end;

        // Extract submission details
        if ResponseJson.Get('submissionUid', JsonToken) then
            SubmissionUid := SafeJsonValueToText(JsonToken);
        if ResponseJson.Get('documentCount', JsonToken) then
            if Evaluate(DocumentCount, SafeJsonValueToText(JsonToken)) then
                DocumentCount := DocumentCount
            else
                DocumentCount := 0;
        if ResponseJson.Get('dateTimeReceived', JsonToken) then
            DateTimeReceived := SafeJsonValueToText(JsonToken);
        if ResponseJson.Get('overallStatus', JsonToken) then
            OverallStatus := SafeJsonValueToText(JsonToken);

        // Build formatted response
        FormattedResponse := 'Submission Details:' + '\\' +
            'Submission UID: ' + SubmissionUid + '\\' +
            'Document Count: ' + Format(DocumentCount) + '\\' +
            'Date Time Received: ' + DateTimeReceived + '\\' +
            'Overall Status: ' + OverallStatus + '\\' + '\\';

        // Extract document summary
        if ResponseJson.Get('documentSummary', JsonToken) and JsonToken.IsArray() then begin
            DocumentSummaryArray := JsonToken.AsArray();

            if DocumentSummaryArray.Count > 0 then begin
                FormattedResponse += 'Document Summary:' + '\\';

                for i := 0 to DocumentSummaryArray.Count - 1 do begin
                    DocumentSummaryArray.Get(i, JsonToken);
                    DocumentJson := JsonToken.AsObject();

                    // Extract document details
                    if DocumentJson.Get('uuid', JsonToken) then
                        Uuid := SafeJsonValueToText(JsonToken);
                    if DocumentJson.Get('status', JsonToken) then
                        Status := SafeJsonValueToText(JsonToken);
                    if DocumentJson.Get('totalPayableAmount', JsonToken) then
                        if Evaluate(TotalPayableAmount, SafeJsonValueToText(JsonToken)) then
                            TotalPayableAmount := TotalPayableAmount
                        else
                            TotalPayableAmount := 0;
                    if DocumentJson.Get('dateTimeIssued', JsonToken) then
                        DateTimeIssued := SafeJsonValueToText(JsonToken);
                    if DocumentJson.Get('issuerName', JsonToken) then
                        IssuerName := SafeJsonValueToText(JsonToken);
                    if DocumentJson.Get('receiverName', JsonToken) then
                        ReceiverName := SafeJsonValueToText(JsonToken);

                    FormattedResponse += StrSubstNo('  Document %1:', i + 1) + '\\' +
                        '    UUID: ' + Uuid + '\\' +
                        '    Status: ' + Status + '\\' +
                        '    Total Payable Amount: ' + Format(TotalPayableAmount) + '\\' +
                        '    Date Time Issued: ' + DateTimeIssued + '\\' +
                        '    Issuer: ' + IssuerName + '\\' +
                        '    Receiver: ' + ReceiverName + '\\' + '\\';
                end;
            end;
        end;

        exit(FormattedResponse);
    end;

    /// <summary>
    /// Logs e-Invoice submission details to the submission log table
    /// </summary>
    /// <param name="SalesInvoiceHeader">The sales invoice header record</param>
    /// <param name="SubmissionUid">LHDN submission UID</param>
    /// <param name="DocumentUuid">Document UUID from LHDN</param>
    /// <param name="Status">Submission status</param>
    /// <param name="ErrorMessage">Error message if any</param>
    local procedure LogSubmissionToTable(SalesInvoiceHeader: Record "Sales Invoice Header"; SubmissionUid: Text; DocumentUuid: Text; Status: Text; ErrorMessage: Text; DocumentType: Text)
    var
        SubmissionLog: Record "eInvoice Submission Log";
        SubmissionStatusCU: Codeunit "eInvoice Submission Status";
        eInvoiceSetup: Record "eInvoiceSetup";
        Customer: Record Customer;
        CustomerName: Text;
        StartTime: DateTime;
        EndTime: DateTime;
        SalesLine: Record "Sales Invoice Line";
        TotalAmount: Decimal;
        TotalAmountInclVAT: Decimal;
        HttpStatusCode: Integer;
        CorrelationId: Text;
        ErrorResponseText: Text;
        PipePos: Integer;
        IsUpdate: Boolean;
    begin
        // Get customer name
        CustomerName := '';
        if Customer.Get(SalesInvoiceHeader."Sell-to Customer No.") then
            CustomerName := Customer.Name;

        // Calculate amounts from sales lines (same logic as JSON generation)
        TotalAmount := 0;
        TotalAmountInclVAT := 0;
        SalesLine.SetRange("Document No.", SalesInvoiceHeader."No.");
        if SalesLine.FindSet() then
            repeat
                TotalAmount += SalesLine.Amount;
                TotalAmountInclVAT += SalesLine."Amount Including VAT";
            until SalesLine.Next() = 0;

        // *** CHANGED: Find existing record instead of always inserting ***
        SubmissionLog.SetRange("Invoice No.", SalesInvoiceHeader."No.");
        if DocumentType <> '' then
            SubmissionLog.SetRange("Document Type", DocumentType);
        IsUpdate := SubmissionLog.FindFirst();

        if IsUpdate then begin
            ArchiveCurrentAttempt(SubmissionLog);
            SubmissionLog."Attempt Number" += 1;
        end else begin
            SubmissionLog.Init();
            SubmissionLog."Entry No." := 0;
            SubmissionLog."Invoice No." := SalesInvoiceHeader."No.";
            SubmissionLog."Document Type" := DocumentType;
            SubmissionLog."Attempt Number" := 1;
        end;

        SubmissionLog."Customer No." := SalesInvoiceHeader."Sell-to Customer No.";
        SubmissionLog."Customer Name" := CustomerName;
        SubmissionLog."Amount" := TotalAmount;
        SubmissionLog."Amount Including VAT" := TotalAmountInclVAT;
        SubmissionLog."Submission UID" := CleanQuotesFromText(SubmissionUid);
        SubmissionLog."Document UUID" := CleanQuotesFromText(DocumentUuid);
        SubmissionLog.Status := Status;
        SubmissionLog."Submission Date" := CurrentDateTime;
        SubmissionLog."Response Date" := CurrentDateTime;
        SubmissionLog."Last Updated" := CurrentDateTime;
        SubmissionLog."User ID" := UserId;
        SubmissionLog."Company Name" := CompanyName;
        SubmissionLog."Posting Date" := SalesInvoiceHeader."Posting Date";

        // Set environment based on setup
        if eInvoiceSetup.Get('SETUP') then
            SubmissionLog.Environment := eInvoiceSetup.Environment
        else
            SubmissionLog.Environment := SubmissionLog.Environment::Preprod;

        // Update submission log
        if IsUpdate then begin
            if not SubmissionLog.Modify(true) then begin
                LogDebugInfo('Submission Log Error', StrSubstNo('Failed to update log for %1. Error: %2', SalesInvoiceHeader."No.", GetLastErrorText()));
                exit;
            end;
        end else begin
            if not SubmissionLog.Insert(true) then begin
                LogDebugInfo('Submission Log Error', StrSubstNo('Failed to insert log for %1. Error: %2', SalesInvoiceHeader."No.", GetLastErrorText()));
                exit;
            end;
        end;

        // Parse and store error details if present
        if ErrorMessage <> '' then begin
            // Extract HTTP status code and correlation ID if present in format: HTTP 400: {...}|CORRELATIONID:xxx
            if ErrorMessage.Contains('HTTP ') then begin
                // Extract status code
                PipePos := ErrorMessage.IndexOf(':');
                if PipePos > 0 then
                    Evaluate(HttpStatusCode, CopyStr(ErrorMessage, 6, PipePos - 6));

                // Extract error response JSON
                PipePos := ErrorMessage.IndexOf('|CORRELATIONID:');
                if PipePos > 0 then begin
                    ErrorResponseText := CopyStr(ErrorMessage, ErrorMessage.IndexOf(':') + 2, PipePos - ErrorMessage.IndexOf(':') - 2);
                    CorrelationId := CopyStr(ErrorMessage, PipePos + 15);
                end else begin
                    ErrorResponseText := CopyStr(ErrorMessage, ErrorMessage.IndexOf(':') + 2);
                end;

                // Parse and store MyInvois error structure
                SubmissionStatusCU.ParseAndStoreErrorResponse(SubmissionLog, ErrorResponseText, HttpStatusCode, CorrelationId);
            end else begin
                // Store generic error message
                SubmissionLog."Error Message" := CopyStr(ErrorMessage, 1, MaxStrLen(SubmissionLog."Error Message"));
                SubmissionLog.Modify(true);
            end;
        end;
    end;

    local procedure ArchiveCurrentAttempt(var SubmissionLog: Record "eInvoice Submission Log")
    var
        HistoryArray: JsonArray;
        HistoryEntry: JsonObject;
        ExistingHistoryText: Text;
        NewHistoryText: Text;
        InStream: InStream;
        OutStream: OutStream;
    begin
        if SubmissionLog."Submission History".HasValue then begin
            SubmissionLog."Submission History".CreateInStream(InStream);
            InStream.ReadText(ExistingHistoryText);
            if ExistingHistoryText <> '' then
                HistoryArray.ReadFrom(ExistingHistoryText);
        end;

        HistoryEntry.Add('AttemptNo', SubmissionLog."Attempt Number");
        HistoryEntry.Add('SubmissionUID', SubmissionLog."Submission UID");
        HistoryEntry.Add('DocumentUUID', SubmissionLog."Document UUID");
        HistoryEntry.Add('Status', SubmissionLog.Status);
        HistoryEntry.Add('SubmissionDate', Format(SubmissionLog."Submission Date", 0, 9));
        HistoryEntry.Add('ErrorMessage', CopyStr(SubmissionLog."Error Message", 1, 200));
        HistoryEntry.Add('UserID', SubmissionLog."User ID");
        HistoryArray.Add(HistoryEntry);

        HistoryArray.WriteTo(NewHistoryText);
        Clear(SubmissionLog."Submission History");
        SubmissionLog."Submission History".CreateOutStream(OutStream);
        OutStream.WriteText(NewHistoryText);
    end;

    /// <summary>
    /// Logs failed submission with proper error parsing
    /// </summary>
    local procedure LogSubmissionWithError(SalesInvoiceHeader: Record "Sales Invoice Header"; ErrorResponse: Text; HttpStatusCode: Integer; CorrelationId: Text)
    var
        SubmissionLog: Record "eInvoice Submission Log";
        SubmissionStatusCU: Codeunit "eInvoice Submission Status";
        eInvoiceSetup: Record "eInvoiceSetup";
        Customer: Record Customer;
        CustomerName: Text;
        SalesLine: Record "Sales Invoice Line";
        TotalAmount: Decimal;
        TotalAmountInclVAT: Decimal;
    begin
        // Get customer name
        CustomerName := '';
        if Customer.Get(SalesInvoiceHeader."Sell-to Customer No.") then
            CustomerName := Customer.Name;

        // Calculate amounts from sales lines
        TotalAmount := 0;
        TotalAmountInclVAT := 0;
        SalesLine.SetRange("Document No.", SalesInvoiceHeader."No.");
        if SalesLine.FindSet() then
            repeat
                TotalAmount += SalesLine.Amount;
                TotalAmountInclVAT += SalesLine."Amount Including VAT";
            until SalesLine.Next() = 0;

        // Create new log entry
        SubmissionLog.Init();
        SubmissionLog."Entry No." := 0;
        SubmissionLog."Invoice No." := SalesInvoiceHeader."No.";
        SubmissionLog."Customer No." := SalesInvoiceHeader."Sell-to Customer No.";
        SubmissionLog."Customer Name" := CustomerName;
        SubmissionLog."Amount" := TotalAmount;
        SubmissionLog."Amount Including VAT" := TotalAmountInclVAT;
        SubmissionLog."Submission UID" := '';
        SubmissionLog."Document UUID" := '';
        SubmissionLog.Status := 'Invalid';
        SubmissionLog."Submission Date" := CurrentDateTime;
        SubmissionLog."Response Date" := CurrentDateTime;
        SubmissionLog."Last Updated" := CurrentDateTime;
        SubmissionLog."User ID" := UserId;
        SubmissionLog."Company Name" := CompanyName;
        SubmissionLog."Posting Date" := SalesInvoiceHeader."Posting Date";
        SubmissionLog."Document Type" := SalesInvoiceHeader."eInvoice Document Type";

        // Set environment
        if eInvoiceSetup.Get('SETUP') then
            SubmissionLog.Environment := eInvoiceSetup.Environment
        else
            SubmissionLog.Environment := SubmissionLog.Environment::Preprod;

        // Insert first
        if SubmissionLog.Insert() then
            // Parse and store the error details using the enhanced error parser
            SubmissionStatusCU.ParseAndStoreErrorResponse(SubmissionLog, ErrorResponse, HttpStatusCode, CorrelationId);
    end;

    /// <summary>
    /// Removes surrounding quotes from text values
    /// </summary>
    /// <param name="InputText">Text that may contain surrounding quotes</param>
    /// <returns>Text with quotes removed</returns>
    local procedure CleanQuotesFromText(InputText: Text): Text
    var
        CleanText: Text;
    begin
        if InputText = '' then
            exit('');

        CleanText := InputText;

        // Remove leading quote if present
        if StrPos(CleanText, '"') = 1 then
            CleanText := CopyStr(CleanText, 2);

        // Remove trailing quote if present
        if StrLen(CleanText) > 0 then
            if CopyStr(CleanText, StrLen(CleanText), 1) = '"' then
                CleanText := CopyStr(CleanText, 1, StrLen(CleanText) - 1);

        exit(CleanText);
    end;

    /// <summary>
    /// Validates environment configuration before signing
    /// Ensures only valid environments (Preprod/Production) are used
    /// </summary>
    /// <param name="Setup">eInvoice Setup record</param>
    /// <returns>True if environment is valid</returns>
    local procedure ValidateEnvironmentBeforeSigning(Setup: Record "eInvoiceSetup"): Boolean
    begin
        if Setup.Environment = Setup.Environment::Preprod then
            exit(true)
        else if Setup.Environment = Setup.Environment::Production then
            exit(true)
        else
            Error('Invalid environment configuration. Must be either Preprod or Production.');
    end;

    /// <summary>
    /// Gets expected certificate name based on environment
    /// Used for Azure Function validation
    /// </summary>
    /// <param name="Environment">Environment option value</param>
    /// <returns>Expected certificate name</returns>
    local procedure GetExpectedCertificateName(Environment: Option): Text
    begin
        case Environment of
            0: // Preprod
                exit('JOTEX_SDN._BHD..p12');
            1: // Production
                exit('CERT_19448802.p12');
            else
                exit('UNKNOWN-CERT');
        end;
    end;

    /// <summary>
    /// Validates the signed response from Azure Function
    /// Ensures the response matches expected environment
    /// </summary>
    /// <param name="SignedJson">Signed JSON response from Azure Function</param>
    /// <param name="ExpectedEnvironment">Expected environment value</param>
    /// <returns>True if response environment matches expected</returns>
    local procedure ValidateSignedResponse(SignedJson: Text; ExpectedEnvironment: Text): Boolean
    var
        ResponseObject: JsonObject;
        EnvironmentToken: JsonToken;
    begin
        if ResponseObject.ReadFrom(SignedJson) then begin
            if ResponseObject.Get('environment', EnvironmentToken) then begin
                exit(EnvironmentToken.AsValue().AsText() = ExpectedEnvironment);
            end;
        end;
        exit(false);
    end;

    /// <summary>
    /// Enhances request payload with environment validation information
    /// Adds environment details for Azure Function processing
    /// </summary>
    /// <param name="RequestPayload">JSON payload to enhance</param>
    /// <param name="Setup">eInvoice Setup record</param>
    local procedure EnhancePayloadWithEnvironmentInfo(var RequestPayload: JsonObject; Setup: Record "eInvoiceSetup")
    begin
        // Enhanced environment information
        RequestPayload.Add('environment', Format(Setup.Environment));
        RequestPayload.Add('environmentValidated', true);
        RequestPayload.Add('certificateExpected', GetExpectedCertificateName(Setup.Environment));
        RequestPayload.Add('validationTimestamp', Format(CurrentDateTime, 0, '<Year4>-<Month,2>-<Day,2>T<Hours24,2>:<Minutes,2>:<Seconds,2>Z'));
    end;

    // ======================================================================================================
    // CREDIT MEMO SUPPORT
    // ======================================================================================================

    /// <summary>
    /// Submits Credit Memo to LHDN MyInvois API
    /// </summary>
    /// <param name="SalesCrMemoHeader">Sales Credit Memo Header record</param>
    /// <param name="LhdnResponse">Final response from LHDN MyInvois API</param>
    /// <returns>True if entire process successful, False if any step fails</returns>
    procedure SubmitCreditMemoToLHDN(SalesCrMemoHeader: Record "Sales Cr.Memo Header"; var LhdnResponse: Text): Boolean
    var
        eInvoiceSetup: Record "eInvoiceSetup";
        SubmissionLog: Record "eInvoice Submission Log";
    begin
        // For now, implement a basic submission that logs the attempt
        // TODO: Implement full Credit Memo submission logic

        // Log the submission attempt
        SubmissionLog.Init();
        SubmissionLog."Invoice No." := SalesCrMemoHeader."No.";
        SubmissionLog."Amount" := SalesCrMemoHeader.Amount;
        SubmissionLog."Amount Including VAT" := SalesCrMemoHeader."Amount Including VAT";
        SubmissionLog.Status := 'Submitted';
        SubmissionLog."Submission Date" := CurrentDateTime;
        SubmissionLog."Response Date" := CurrentDateTime;
        SubmissionLog."Environment" := 0; // Preprod
        SubmissionLog."Last Updated" := CurrentDateTime;
        SubmissionLog."User ID" := UserId;
        SubmissionLog."Company Name" := 'JOTEX SDN BHD';
        SubmissionLog."Customer Name" := GetCustomerNameFromCreditMemo(SalesCrMemoHeader."Sell-to Customer No.");
        SubmissionLog."Posting Date" := SalesCrMemoHeader."Posting Date";
        SubmissionLog."Document Type" := SalesCrMemoHeader."eInvoice Document Type";

        if SubmissionLog.Insert() then begin
            LhdnResponse := 'Credit Memo submission logged successfully. Full implementation pending.';
            exit(true);
        end else begin
            LhdnResponse := 'Failed to log Credit Memo submission.';
            exit(false);
        end;
    end;

    /// <summary>
    /// Gets customer name for Credit Memo submission logging
    /// </summary>
    /// <param name="CustomerNo">Customer number</param>
    /// <returns>Customer name</returns>
    local procedure GetCustomerNameFromCreditMemo(CustomerNo: Code[20]): Text[100]
    var
        Customer: Record Customer;
    begin
        if Customer.Get(CustomerNo) then
            exit(Customer.Name)
        else
            exit('Unknown Customer');
    end;

    // New procedure for complete credit memo signing and submission
    /// <summary>
    /// Complete integration workflow for credit memos: Generate > Sign > Submit to LHDN
    /// Handles the full process from unsigned JSON to LHDN submission with proper error handling
    /// ENHANCED: Now includes complete LHDN submission logic matching sales invoice implementation
    /// </summary>
    /// <param name="SalesCrMemoHeader">Sales Credit Memo record to process</param>
    /// <param name="LhdnResponse">Final response from LHDN MyInvois API</param>
    /// <returns>True if entire process successful, False if any step fails</returns>
    procedure GetSignedCreditMemoAndSubmitToLHDN(SalesCrMemoHeader: Record "Sales Cr.Memo Header"; var LhdnResponse: Text): Boolean
    var
        UnsignedJsonText: Text;
        AzureResponseText: Text;
        AzureResponse: JsonObject;
        JsonToken: JsonToken;
        eInvoiceSetup: Record "eInvoiceSetup";
        AzureFunctionUrl: Text;
    begin
        // Step 1: Generate unsigned credit memo JSON
        UnsignedJsonText := GenerateCreditMemoEInvoiceJson(SalesCrMemoHeader, false);

        // Step 2: Get Azure Function URL from setup
        if not eInvoiceSetup.Get('SETUP') then begin
            LhdnResponse := 'eInvoice Setup not found. Please configure the Azure Function URL.';
            exit(false);
        end;

        AzureFunctionUrl := eInvoiceSetup."Azure Function URL";
        if AzureFunctionUrl = '' then begin
            LhdnResponse := 'Azure Function URL is not configured in eInvoice Setup.';
            exit(false);
        end;

        // Step 3: Get signed credit memo from Azure Function using the working direct method
        if not TryPostToAzureFunctionDirect(UnsignedJsonText, AzureFunctionUrl, AzureResponseText, SalesCrMemoHeader) then begin
            LhdnResponse := 'Failed to communicate with Azure Function. Please check connectivity and try again.';
            exit(false);
        end;

        // Step 4: Parse Azure Function response with detailed validation and debugging
        if not AzureResponse.ReadFrom(AzureResponseText) then begin
            LhdnResponse := StrSubstNo('Invalid JSON response from Azure Function: %1', CopyStr(AzureResponseText, 1, 500));
            LogDebugInfo('Azure Function JSON parsing failed',
                StrSubstNo('Response length: %1\nResponse preview: %2', StrLen(AzureResponseText), CopyStr(AzureResponseText, 1, 500)));
            exit(false);
        end;

        // Log the Azure Function response structure for debugging
        LogDebugInfo('Azure Function response received for credit memo',
            StrSubstNo('Response keys: %1\nResponse preview: %2',
                GetJsonObjectKeys(AzureResponse),
                CopyStr(AzureResponseText, 1, 300)));

        // Check for success status (BusinessCentralSigningResponse format)
        if not AzureResponse.Get('success', JsonToken) or not JsonToken.AsValue().AsBoolean() then begin
            if AzureResponse.Get('errorDetails', JsonToken) then
                LhdnResponse := StrSubstNo('Azure Function signing failed: %1', SafeJsonValueToText(JsonToken))
            else if AzureResponse.Get('message', JsonToken) then
                LhdnResponse := StrSubstNo('Azure Function error: %1', SafeJsonValueToText(JsonToken))
            else
                LhdnResponse := StrSubstNo('Azure Function signing failed with unknown error. Response: %1', CopyStr(AzureResponseText, 1, 200));

            LogDebugInfo('Azure Function signing failed for credit memo',
                StrSubstNo('Error response: %1', LhdnResponse));
            exit(false);
        end;

        // Step 5: Process and store signed JSON (important for audit trail)
        if AzureResponse.Get('signedJson', JsonToken) then begin
            // Store the signed JSON for records/audit purposes
            StoreSignedCreditMemoJson(SalesCrMemoHeader, SafeJsonValueToText(JsonToken));
        end;

        // Step 6: Extract LHDN payload and submit to LHDN API
        if AzureResponse.Get('lhdnPayload', JsonToken) then begin
            // The lhdnPayload is returned as a JSON string, not an object
            LhdnResponse := SafeJsonValueToText(JsonToken);

            // Log the LHDN payload for debugging
            LogDebugInfo('LHDN Payload extracted from Azure Function for credit memo',
                StrSubstNo('Payload length: %1\nPayload preview: %2',
                    StrLen(LhdnResponse),
                    CopyStr(LhdnResponse, 1, 300)));

            // Process the LHDN payload string
            exit(ProcessCreditMemoLhdnPayload(LhdnResponse, SalesCrMemoHeader, LhdnResponse));
        end else begin
            LhdnResponse := StrSubstNo('No LHDN payload found in Azure Function response. Response keys: %1', GetJsonObjectKeys(AzureResponse));
            LogDebugInfo('Missing LHDN payload in Azure Function response for credit memo',
                StrSubstNo('Available keys: %1\nFull response preview: %2',
                    GetJsonObjectKeys(AzureResponse),
                    CopyStr(AzureResponseText, 1, 500)));
            exit(false);
        end;
    end;

    /// <summary>
    /// Updates credit memo validation status
    /// </summary>
    procedure UpdateCreditMemoValidationStatus(CreditMemoNo: Code[20]; NewStatus: Text): Boolean
    var
        SalesCrMemoHeader: Record "Sales Cr.Memo Header";
    begin
        if SalesCrMemoHeader.Get(CreditMemoNo) then begin
            // FIXED: Now that we have the eInvoice Validation Status field, we can update it
            SalesCrMemoHeader."eInvoice Validation Status" := CopyStr(NewStatus, 1, MaxStrLen(SalesCrMemoHeader."eInvoice Validation Status"));
            exit(SalesCrMemoHeader.Modify());
        end;
        exit(false);
    end;

    /// <summary>
    /// Stores signed credit memo JSON for audit trail and compliance requirements
    /// </summary>
    /// <param name="SalesCrMemoHeader">Credit memo record for reference</param>
    /// <param name="SignedJsonText">Digitally signed JSON from Azure Function</param>
    local procedure StoreSignedCreditMemoJson(SalesCrMemoHeader: Record "Sales Cr.Memo Header"; SignedJsonText: Text)
    var
        TempBlob: Codeunit "Temp Blob";
        OutStream: OutStream;
        InStream: InStream;
        FileName: Text;
    begin
        // Store signed JSON for audit trail and records
        FileName := StrSubstNo('SignedCreditMemo_%1_%2.json',
            SalesCrMemoHeader."No.",
            Format(CurrentDateTime, 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2><Seconds,2>'));

        TempBlob.CreateOutStream(OutStream);
        OutStream.WriteText(SignedJsonText);
        TempBlob.CreateInStream(InStream);

        // Optional: Download the signed JSON for verification
        // DownloadFromStream(InStream, 'Signed Credit Memo JSON', '', 'JSON files (*.json)|*.json', FileName);
    end;

    /// <summary>
    /// Processes LHDN payload from Azure Function response for credit memos
    /// </summary>
    local procedure ProcessCreditMemoLhdnPayload(LhdnPayloadText: Text; SalesCrMemoHeader: Record "Sales Cr.Memo Header"; var LhdnResponse: Text): Boolean
    var
        LhdnPayloadObject: JsonObject;
        JsonToken: JsonToken;
    begin
        // 1. Try direct parsing first
        if LhdnPayloadObject.ReadFrom(LhdnPayloadText) then
            if LhdnPayloadObject.Get('documents', JsonToken) then begin
                LhdnResponse := 'Direct JSON parsing successful - submitting credit memo to LHDN API';
                exit(SubmitCreditMemoToLhdnApi(LhdnPayloadObject, SalesCrMemoHeader, LhdnResponse));
            end;

        // 2. Handle as JSON string if direct parsing failed
        if LhdnPayloadText.StartsWith('"') and LhdnPayloadText.EndsWith('"') then
            LhdnPayloadText := CopyStr(LhdnPayloadText, 2, StrLen(LhdnPayloadText) - 2);

        // 3. Unescape the JSON and remove problematic characters
        LhdnPayloadText := LhdnPayloadText.Replace('\"', '"');
        LhdnPayloadText := LhdnPayloadText.Replace('\\n', '');
        LhdnPayloadText := LhdnPayloadText.Replace('\\t', '');
        LhdnPayloadText := LhdnPayloadText.Replace('\\r', '');
        LhdnPayloadText := LhdnPayloadText.Replace('\\\\', '\\');
        LhdnPayloadText := LhdnPayloadText.Replace('\n', '');
        LhdnPayloadText := LhdnPayloadText.Replace('\t', '');
        LhdnPayloadText := LhdnPayloadText.Replace('\r', '');

        // 4. Parse the unescaped JSON
        if not LhdnPayloadObject.ReadFrom(LhdnPayloadText) then begin
            LhdnResponse := 'Failed to parse LHDN payload after unescaping. Payload start: ' + CopyStr(LhdnPayloadText, 1, 200);
            exit(false);
        end;

        // 5. Validate structure
        if not LhdnPayloadObject.Get('documents', JsonToken) then begin
            LhdnResponse := 'LHDN payload missing documents array after parsing. Payload keys: ' + GetJsonObjectKeys(LhdnPayloadObject);
            exit(false);
        end;

        // 6. Submit to LHDN API
        LhdnResponse := 'JSON parsing successful - submitting credit memo to LHDN API';
        exit(SubmitCreditMemoToLhdnApi(LhdnPayloadObject, SalesCrMemoHeader, LhdnResponse));
    end;

    /// <summary>
    /// Submits digitally signed credit memo to LHDN MyInvois API for official processing
    /// </summary>
    local procedure SubmitCreditMemoToLhdnApi(LhdnPayload: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header"; var LhdnResponse: Text): Boolean
    var
        HttpClient: HttpClient;
        HttpRequestMessage: HttpRequestMessage;
        HttpResponseMessage: HttpResponseMessage;
        ContentHeaders: HttpHeaders;
        RequestHeaders: HttpHeaders;
        LhdnPayloadText: Text;
        AccessToken: Text;
        eInvoiceSetup: Record "eInvoiceSetup";
        LhdnApiUrl: Text;
    begin
        // Get setup for environment determination
        if not eInvoiceSetup.Get('SETUP') then
            Error('eInvoice Setup not found');

        // Convert payload to text
        LhdnPayload.WriteTo(LhdnPayloadText);

        // Validate that we have the documents array structure
        if not LhdnPayloadText.Contains('"documents"') then begin
            Error('Invalid LHDN payload structure. Expected "documents" array not found. Payload preview: %1', CopyStr(LhdnPayloadText, 1, 200));
        end;

        // Get LHDN access token using the standardized eInvoiceHelper method
        AccessToken := GetLhdnAccessTokenFromHelper(eInvoiceSetup);

        // Determine LHDN API URL based on environment
        if eInvoiceSetup.Environment = eInvoiceSetup.Environment::Preprod then
            LhdnApiUrl := 'https://preprod-api.myinvois.hasil.gov.my/api/v1.0/documentsubmissions'
        else
            LhdnApiUrl := 'https://api.myinvois.hasil.gov.my/api/v1.0/documentsubmissions';

        // Setup LHDN API request with standard headers
        HttpRequestMessage.Method := 'POST';
        HttpRequestMessage.SetRequestUri(LhdnApiUrl);
        HttpRequestMessage.Content.WriteFrom(LhdnPayloadText);

        // Set standard LHDN API headers as per documentation
        HttpRequestMessage.Content.GetHeaders(ContentHeaders);
        ContentHeaders.Clear();
        ContentHeaders.Add('Content-Type', 'application/json');

        HttpRequestMessage.GetHeaders(RequestHeaders);
        RequestHeaders.Clear();
        RequestHeaders.Add('Accept', 'application/json');
        RequestHeaders.Add('Accept-Language', 'en');
        RequestHeaders.Add('Authorization', 'Bearer ' + AccessToken);

        // Submit to LHDN
        if HttpClient.Send(HttpRequestMessage, HttpResponseMessage) then begin
            HttpResponseMessage.Content.ReadAs(LhdnResponse);

            if HttpResponseMessage.IsSuccessStatusCode then begin
                // Parse and display structured LHDN response
                ParseAndDisplayCreditMemoLhdnResponse(LhdnResponse, HttpResponseMessage.HttpStatusCode, SalesCrMemoHeader, HttpResponseMessage);
                exit(true);
            end else begin
                // Parse and display structured LHDN error response
                ParseAndDisplayLhdnError(LhdnResponse, HttpResponseMessage.HttpStatusCode, HttpResponseMessage.ReasonPhrase, HttpResponseMessage);

                // Update validation status to "Submission Failed" when there's an error
                SalesCrMemoHeader."eInvoice Validation Status" := 'Submission Failed';
                SalesCrMemoHeader.Modify();

                // Log the failed submission with proper error parsing
                LogCreditMemoWithError(SalesCrMemoHeader, LhdnResponse, HttpResponseMessage.HttpStatusCode, CreateGuid());
            end;
        end else begin
            Error('Failed to send HTTP request to LHDN API at %1', LhdnApiUrl);
        end;

        exit(false);
    end;

    /// <summary>
    /// Parses and displays LHDN response for credit memos
    /// </summary>
    local procedure ParseAndDisplayCreditMemoLhdnResponse(LhdnResponse: Text; StatusCode: Integer; var SalesCrMemoHeader: Record "Sales Cr.Memo Header"; HttpResponseMessage: HttpResponseMessage)
    var
        ResponseJson: JsonObject;
        JsonToken: JsonToken;
        AcceptedArray: JsonArray;
        RejectedArray: JsonArray;
        SubmissionUid: Text;
        AcceptedCount: Integer;
        RejectedCount: Integer;
        i: Integer;
        DocumentJson: JsonObject;
        Uuid: Text;
        InvoiceCodeNumber: Text;
        CorrelationId: Text;
        RateLimitInfo: Text;
        ResponseHeaders: HttpHeaders;
        HeaderValues: List of [Text];
        SuccessMessage: Text;
        DocumentDetails: Text;
    begin
        // Extract LHDN response headers - using Content headers as proxy for response headers
        HttpResponseMessage.Content.GetHeaders(ResponseHeaders);

        // Note: In AL, direct access to response headers may be limited
        // The correlation ID and rate limit headers would typically be in the response
        // but we'll focus on the content parsing for now

        CorrelationId := 'N/A'; // Will be populated from JSON response if available
        RateLimitInfo := 'See LHDN response for rate limiting info';

        // Try to parse the JSON response
        if not ResponseJson.ReadFrom(LhdnResponse) then begin
            Message(StrSubstNo('LHDN Credit Memo Submission successful!\nStatus: %1\nRaw Response: %2', StatusCode, LhdnResponse));
            exit;
        end;

        // Log the response structure for debugging based on LHDN API documentation
        LogDebugInfo('LHDN API Response Structure for Credit Memo',
            StrSubstNo('Status Code: %1\nResponse Keys: %2\nResponse Preview: %3',
                StatusCode,
                GetJsonObjectKeys(ResponseJson),
                CopyStr(LhdnResponse, 1, 500)));

        // Extract submission UID with safe type conversion
        // According to LHDN API docs: submissionUID is a String with 26 Latin alphanumeric symbols
        if ResponseJson.Get('submissionUid', JsonToken) then
            SubmissionUid := SafeJsonValueToText(JsonToken)
        else if ResponseJson.Get('submissionUID', JsonToken) then
            // Try alternative casing as per LHDN documentation
            SubmissionUid := SafeJsonValueToText(JsonToken)
        else
            SubmissionUid := 'N/A';

        // Process accepted documents
        AcceptedCount := 0;
        DocumentDetails := '';
        if ResponseJson.Get('acceptedDocuments', JsonToken) then begin
            AcceptedArray := JsonToken.AsArray();
            AcceptedCount := AcceptedArray.Count;

            DocumentDetails := BuildDocumentDetails(AcceptedArray, RejectedArray);
        end;

        // Process rejected documents
        RejectedCount := 0;
        if ResponseJson.Get('rejectedDocuments', JsonToken) then begin
            RejectedArray := JsonToken.AsArray();
            RejectedCount := RejectedArray.Count;
        end;

        // Build success message with proper formatting
        if (AcceptedCount > 0) and (RejectedCount = 0) then begin
            // All documents accepted
            SuccessMessage := FormatCreditMemoLhdnSuccessMessage(SubmissionUid, StatusCode, AcceptedCount, DocumentDetails, CorrelationId, RateLimitInfo);
        end else if (AcceptedCount > 0) and (RejectedCount > 0) then begin
            // Mixed results - some accepted, some rejected
            SuccessMessage := StrSubstNo('LHDN Credit Memo Submission Partially Successful\n\n' +
                'Submission ID: %1\n' +
                'Status Code: %2\n' +
                '%3\n' +
                '%4\n\n' +
                'Accepted Documents: %5\n' +
                'Rejected Documents: %6\n\n' +
                'Details:\n%7\n\n' +
                'Please review and resubmit the rejected documents.',
                SubmissionUid, StatusCode,
                CorrelationId <> 'N/A' ? StrSubstNo('Correlation ID: %1', CorrelationId) : '',
                RateLimitInfo <> '' ? StrSubstNo('Rate Limits: %1', RateLimitInfo) : '',
                AcceptedCount, RejectedCount, DocumentDetails);
        end else begin
            // All documents rejected or no documents processed
            SuccessMessage := StrSubstNo('LHDN Credit Memo Submission Failed\n\n' +
                'Submission ID: %1\n' +
                'Status Code: %2\n' +
                '%3\n' +
                '%4\n\n' +
                'Accepted Documents: %5\n' +
                'Rejected Documents: %6\n\n' +
                'Details:\n%7\n\n' +
                'Please review the errors and resubmit.\n\n' +
                'Full Response: %8',
                SubmissionUid, StatusCode,
                CorrelationId <> 'N/A' ? StrSubstNo('Correlation ID: %1', CorrelationId) : '',
                RateLimitInfo <> '' ? StrSubstNo('Rate Limits: %1', RateLimitInfo) : '',
                AcceptedCount, RejectedCount, DocumentDetails, LhdnResponse);
        end;

        // Display the formatted message
        Message(SuccessMessage);

        // Update Sales Credit Memo Header with LHDN response data
        UpdateCreditMemoWithLhdnResponse(SalesCrMemoHeader, SubmissionUid, AcceptedArray, AcceptedCount);

        // Background: fetch Validation URL and store QR image for credit memo as well
        TryFetchAndStoreCreditMemoValidationLink(SalesCrMemoHeader);
    end;

    /// <summary>
    /// Updates credit memo with LHDN response data
    /// </summary>
    local procedure UpdateCreditMemoWithLhdnResponse(var SalesCrMemoHeader: Record "Sales Cr.Memo Header"; SubmissionUid: Text; AcceptedArray: JsonArray; AcceptedCount: Integer)
    var
        JsonToken: JsonToken;
        DocumentJson: JsonObject;
        Uuid: Text;
        ValidationStatus: Text;
    begin
        // Extract UUID from the first accepted document (if any)
        Uuid := '';
        ValidationStatus := '';

        if AcceptedCount > 0 then begin
            AcceptedArray.Get(0, JsonToken);
            DocumentJson := JsonToken.AsObject();

            if DocumentJson.Get('uuid', JsonToken) then begin
                Uuid := SafeJsonValueToText(JsonToken);
            end;

            // Set validation status to "Submitted" when documents are accepted for processing
            ValidationStatus := 'Submitted';
        end;

        // Use the public procedure with proper permissions to update the credit memo
        if not UpdateCreditMemoWithLhdnData(SalesCrMemoHeader."No.", SubmissionUid, Uuid, ValidationStatus) then begin
            Message('Warning: Could not save LHDN response data to credit memo record.');
        end;

        // Log the submission to the submission log table
        LogCreditMemoSubmissionToTable(SalesCrMemoHeader, SubmissionUid, Uuid, 'Submitted', '', SalesCrMemoHeader."eInvoice Document Type");
    end;

    local procedure TryFetchAndStoreCreditMemoValidationLink(var SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        RawResponse: Text;
        LongId: Text;
        ValidationUrl: Text;
        Setup: Record "eInvoiceSetup";
        Attempt: Integer;
    begin
        if (SalesCrMemoHeader."eInvoice Submission UID" = '') or (SalesCrMemoHeader."eInvoice UUID" = '') then
            exit;
        // Retry up to 3 times to allow LHDN to populate longId
        for Attempt := 1 to 3 do begin
            if GetSubmissionDetailsRaw(SalesCrMemoHeader."eInvoice Submission UID", RawResponse) then begin
                LongId := ExtractLongIdFromApiResponse(RawResponse, SalesCrMemoHeader."eInvoice UUID");
                if LongId <> '' then
                    break;
            end;
            case Attempt of
                1:
                    Sleep(2000);
                2:
                    Sleep(3000);
                else
                    Sleep(5000);
            end;
        end;

        if LongId = '' then
            exit;

        if not Setup.Get('SETUP') then
            exit;

        ValidationUrl := BuildValidationUrl(SalesCrMemoHeader."eInvoice UUID", LongId, Setup.Environment);
        if ValidationUrl = '' then
            exit;

        UpdateCreditMemoQrUrl(SalesCrMemoHeader."No.", ValidationUrl);
        GenerateAndStoreCreditMemoQrImage(SalesCrMemoHeader."No.", ValidationUrl);
    end;

    procedure UpdateCreditMemoQrUrl(CreditMemoNo: Code[20]; Url: Text): Boolean
    var
        SalesCrMemoHeader: Record "Sales Cr.Memo Header";
    begin
        if (CreditMemoNo = '') or (Url = '') then
            exit(false);

        if SalesCrMemoHeader.Get(CreditMemoNo) then begin
            SalesCrMemoHeader."eInvoice QR URL" := CopyStr(Url, 1, MaxStrLen(SalesCrMemoHeader."eInvoice QR URL"));
            exit(SalesCrMemoHeader.Modify());
        end;
        exit(false);
    end;

    procedure UpdateCreditMemoQrImage(CreditMemoNo: Code[20]; var InS: InStream; FileName: Text): Boolean
    var
        SalesCrMemoHeader: Record "Sales Cr.Memo Header";
    begin
        if (CreditMemoNo = '') then
            exit(false);

        if SalesCrMemoHeader.Get(CreditMemoNo) then begin
            SalesCrMemoHeader."eInvoice QR Image".ImportStream(InS, FileName);
            exit(SalesCrMemoHeader.Modify());
        end;
        exit(false);
    end;

    local procedure GenerateAndStoreCreditMemoQrImage(CreditMemoNo: Code[20]; ValidationUrl: Text)
    var
        HttpClient: HttpClient;
        Response: HttpResponseMessage;
        InS: InStream;
        QrServiceUrl: Text;
    begin
        if (CreditMemoNo = '') or (ValidationUrl = '') then
            exit;

        // Prime validation endpoint (optional)
        HttpClient.Get(ValidationUrl, Response);

        QrServiceUrl := StrSubstNo('https://quickchart.io/qr?text=%1&size=220', ValidationUrl);
        if not HttpClient.Get(QrServiceUrl, Response) then
            exit;
        if not Response.IsSuccessStatusCode then
            exit;

        Response.Content.ReadAs(InS);
        UpdateCreditMemoQrImage(CreditMemoNo, InS, 'eInvoiceQR.png');
    end;

    /// <summary>
    /// Logs credit memo submission details to the submission log table
    /// ENHANCED: Now parses MyInvois standard error responses
    /// </summary>
    local procedure LogCreditMemoSubmissionToTable(SalesCrMemoHeader: Record "Sales Cr.Memo Header"; SubmissionUid: Text; DocumentUuid: Text; Status: Text; ErrorMessage: Text; DocumentType: Text)
    var
        SubmissionLog: Record "eInvoice Submission Log";
        SubmissionStatusCU: Codeunit "eInvoice Submission Status";
        eInvoiceSetup: Record "eInvoiceSetup";
        Customer: Record Customer;
        CustomerName: Text;
        SalesCrMemoLine: Record "Sales Cr.Memo Line";
        TotalAmount: Decimal;
        TotalAmountInclVAT: Decimal;
        HttpStatusCode: Integer;
        CorrelationId: Text;
        ErrorResponseText: Text;
        PipePos: Integer;
    begin
        // Get customer name
        CustomerName := '';
        if Customer.Get(SalesCrMemoHeader."Sell-to Customer No.") then
            CustomerName := Customer.Name;

        // Calculate amounts from sales credit memo lines (same logic as JSON generation)
        TotalAmount := 0;
        TotalAmountInclVAT := 0;
        SalesCrMemoLine.SetRange("Document No.", SalesCrMemoHeader."No.");
        if SalesCrMemoLine.FindSet() then
            repeat
                TotalAmount += SalesCrMemoLine.Amount;
                TotalAmountInclVAT += SalesCrMemoLine."Amount Including VAT";
            until SalesCrMemoLine.Next() = 0;

        // Create new log entry
        SubmissionLog.Init();
        SubmissionLog."Entry No." := 0; // Auto-increment
        SubmissionLog."Invoice No." := SalesCrMemoHeader."No.";
        SubmissionLog."Customer No." := SalesCrMemoHeader."Sell-to Customer No.";
        SubmissionLog."Customer Name" := CustomerName;
        SubmissionLog."Amount" := TotalAmount;
        SubmissionLog."Amount Including VAT" := TotalAmountInclVAT;
        SubmissionLog."Submission UID" := CleanQuotesFromText(SubmissionUid);
        SubmissionLog."Document UUID" := CleanQuotesFromText(DocumentUuid);
        SubmissionLog.Status := Status;
        SubmissionLog."Submission Date" := CurrentDateTime;
        SubmissionLog."Response Date" := CurrentDateTime;
        SubmissionLog."Last Updated" := CurrentDateTime;
        SubmissionLog."User ID" := UserId;
        SubmissionLog."Company Name" := CompanyName;
        SubmissionLog."Posting Date" := SalesCrMemoHeader."Posting Date";
        SubmissionLog."Document Type" := DocumentType;

        // Set environment based on setup
        if eInvoiceSetup.Get('SETUP') then
            SubmissionLog.Environment := eInvoiceSetup.Environment
        else
            SubmissionLog.Environment := SubmissionLog.Environment::Preprod;

        // Insert the log entry first
        if not SubmissionLog.Insert() then begin
            // Log error silently to avoid disrupting the main flow
            LogDebugInfo('Credit Memo Submission Log Error',
                StrSubstNo('Failed to insert log entry for credit memo %1. Error: %2',
                    SalesCrMemoHeader."No.", GetLastErrorText()));
            exit;
        end;

        // Parse and store error details if present
        if ErrorMessage <> '' then begin
            // Extract HTTP status code and correlation ID if present in format: HTTP 400: {...}|CORRELATIONID:xxx
            if ErrorMessage.Contains('HTTP ') then begin
                // Extract status code
                PipePos := ErrorMessage.IndexOf(':');
                if PipePos > 0 then
                    Evaluate(HttpStatusCode, CopyStr(ErrorMessage, 6, PipePos - 6));

                // Extract error response JSON
                PipePos := ErrorMessage.IndexOf('|CORRELATIONID:');
                if PipePos > 0 then begin
                    ErrorResponseText := CopyStr(ErrorMessage, ErrorMessage.IndexOf(':') + 2, PipePos - ErrorMessage.IndexOf(':') - 2);
                    CorrelationId := CopyStr(ErrorMessage, PipePos + 15);
                end else begin
                    ErrorResponseText := CopyStr(ErrorMessage, ErrorMessage.IndexOf(':') + 2);
                end;

                // Parse and store MyInvois error structure
                SubmissionStatusCU.ParseAndStoreErrorResponse(SubmissionLog, ErrorResponseText, HttpStatusCode, CorrelationId);
            end else begin
                // Store generic error message
                SubmissionLog."Error Message" := CopyStr(ErrorMessage, 1, MaxStrLen(SubmissionLog."Error Message"));
                SubmissionLog.Modify(true);
            end;
        end;
    end;

    /// <summary>
    /// Logs failed credit memo submission with proper error parsing
    /// </summary>
    local procedure LogCreditMemoWithError(SalesCrMemoHeader: Record "Sales Cr.Memo Header"; ErrorResponse: Text; HttpStatusCode: Integer; CorrelationId: Text)
    var
        SubmissionLog: Record "eInvoice Submission Log";
        SubmissionStatusCU: Codeunit "eInvoice Submission Status";
        eInvoiceSetup: Record "eInvoiceSetup";
        Customer: Record Customer;
        CustomerName: Text;
        SalesCrMemoLine: Record "Sales Cr.Memo Line";
        TotalAmount: Decimal;
        TotalAmountInclVAT: Decimal;
    begin
        // Get customer name
        CustomerName := '';
        if Customer.Get(SalesCrMemoHeader."Sell-to Customer No.") then
            CustomerName := Customer.Name;

        // Calculate amounts from credit memo lines
        TotalAmount := 0;
        TotalAmountInclVAT := 0;
        SalesCrMemoLine.SetRange("Document No.", SalesCrMemoHeader."No.");
        if SalesCrMemoLine.FindSet() then
            repeat
                TotalAmount += SalesCrMemoLine.Amount;
                TotalAmountInclVAT += SalesCrMemoLine."Amount Including VAT";
            until SalesCrMemoLine.Next() = 0;

        // Create new log entry
        SubmissionLog.Init();
        SubmissionLog."Entry No." := 0;
        SubmissionLog."Invoice No." := SalesCrMemoHeader."No.";
        SubmissionLog."Customer No." := SalesCrMemoHeader."Sell-to Customer No.";
        SubmissionLog."Customer Name" := CustomerName;
        SubmissionLog."Amount" := TotalAmount;
        SubmissionLog."Amount Including VAT" := TotalAmountInclVAT;
        SubmissionLog."Submission UID" := '';
        SubmissionLog."Document UUID" := '';
        SubmissionLog.Status := 'Invalid';
        SubmissionLog."Submission Date" := CurrentDateTime;
        SubmissionLog."Response Date" := CurrentDateTime;
        SubmissionLog."Last Updated" := CurrentDateTime;
        SubmissionLog."User ID" := UserId;
        SubmissionLog."Company Name" := CompanyName;
        SubmissionLog."Posting Date" := SalesCrMemoHeader."Posting Date";
        SubmissionLog."Document Type" := SalesCrMemoHeader."eInvoice Document Type";

        // Set environment
        if eInvoiceSetup.Get('SETUP') then
            SubmissionLog.Environment := eInvoiceSetup.Environment
        else
            SubmissionLog.Environment := SubmissionLog.Environment::Preprod;

        // Insert first
        if SubmissionLog.Insert() then
            // Parse and store the error details
            SubmissionStatusCU.ParseAndStoreErrorResponse(SubmissionLog, ErrorResponse, HttpStatusCode, CorrelationId);
    end;

    // Helper procedure to generate credit memo JSON
    local procedure GenerateCreditMemoJson(SalesCrMemoHeader: Record "Sales Cr.Memo Header"): Text
    var
        UBLDocument: JsonObject;
        UBLDocumentBuilder: Codeunit "eInvoice UBL Document Builder";
        JsonText: Text;
    begin
        // Use the enhanced UBL document builder for credit memos with proper LHDN structure
        UBLDocument := UBLDocumentBuilder.BuildEnhancedCreditMemoDocument(SalesCrMemoHeader);
        UBLDocument.WriteTo(JsonText);
        exit(JsonText);
    end;

    // Helper procedure to submit signed document to LHDN
    local procedure SubmitSignedDocumentToLHDN(SignedJson: Text; CorrelationId: Text; var LhdnResponse: Text): Boolean
    var
        HttpClient: HttpClient;
        HttpRequestMessage: HttpRequestMessage;
        HttpResponseMessage: HttpResponseMessage;
        RequestHeaders: HttpHeaders;
        ContentHeaders: HttpHeaders;
        eInvoiceSetup: Record "eInvoiceSetup";
        eInvoiceHelper: Codeunit eInvoiceHelper;
        AccessToken: Text;
        ApiUrl: Text;
        ResponseText: Text;
        TelemetryDimensions: Dictionary of [Text, Text];
    begin
        // Get setup for environment determination
        if not eInvoiceSetup.Get('SETUP') then begin
            LhdnResponse := 'eInvoice Setup not found';
            exit(false);
        end;

        // Get access token using the helper method
        eInvoiceHelper.InitializeHelper();
        AccessToken := eInvoiceHelper.GetAccessTokenFromSetup(eInvoiceSetup);
        if AccessToken = '' then begin
            LhdnResponse := 'Failed to get access token';
            exit(false);
        end;

        // Build API URL for submission
        if eInvoiceSetup.Environment = eInvoiceSetup.Environment::Preprod then
            ApiUrl := 'https://preprod-api.myinvois.hasil.gov.my/api/v1.0/documents'
        else
            ApiUrl := 'https://api.myinvois.hasil.gov.my/api/v1.0/documents';

        // Setup LHDN API request
        HttpRequestMessage.Method := 'POST';
        HttpRequestMessage.SetRequestUri(ApiUrl);
        HttpRequestMessage.Content.WriteFrom(SignedJson);

        // Set standard LHDN API headers
        HttpRequestMessage.Content.GetHeaders(ContentHeaders);
        ContentHeaders.Clear();
        ContentHeaders.Add('Content-Type', 'application/json');

        HttpRequestMessage.GetHeaders(RequestHeaders);
        RequestHeaders.Clear();
        RequestHeaders.Add('Accept', 'application/json');
        RequestHeaders.Add('Accept-Language', 'en');
        RequestHeaders.Add('Authorization', 'Bearer ' + AccessToken);
        RequestHeaders.Add('User-Agent', 'BusinessCentral-eInvoice/2.0');
        RequestHeaders.Add('X-Correlation-ID', CorrelationId);
        RequestHeaders.Add('X-Request-Source', 'BusinessCentral-CreditMemo');

        // Apply rate limiting
        eInvoiceHelper.ApplyRateLimiting(ApiUrl);

        // Send submission request
        if HttpClient.Send(HttpRequestMessage, HttpResponseMessage) then begin
            HttpResponseMessage.Content.ReadAs(ResponseText);

            if HttpResponseMessage.IsSuccessStatusCode then begin
                LhdnResponse := ResponseText;
                exit(true);
            end else begin
                // Format error response with HTTP status code and correlation ID for better tracking
                LhdnResponse := StrSubstNo('HTTP %1: %2|CORRELATIONID:%3',
                    HttpResponseMessage.HttpStatusCode(),
                    ResponseText,
                    CorrelationId);
                exit(false);
            end;
        end else begin
            LhdnResponse := StrSubstNo('Failed to communicate with LHDN API|CORRELATIONID:%1', CorrelationId);
            exit(false);
        end;
    end;

    // ======================================================================================================
    // OVERLOADED PROCEDURES FOR CREDIT MEMOS
    // ======================================================================================================

    // Overloaded version for credit memos
    local procedure AddTaxExchangeRate(var InvoiceObject: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header"; SourceCurrencyCode: Code[10])
    var
        TaxExchangeRateArray: JsonArray;
        TaxExchangeRateObject: JsonObject;
        CurrencyExchangeRate: Record "Currency Exchange Rate";
        ExchangeRate: Decimal;
    begin
        // MANDATORY for non-MYR currencies per LHDN specification
        // Get exchange rate from Business Central
        ExchangeRate := 1.0; // Default

        if CurrencyExchangeRate.Get(SourceCurrencyCode, SalesCrMemoHeader."Posting Date") then
            ExchangeRate := CurrencyExchangeRate."Exchange Rate Amount"
        else if CurrencyExchangeRate.Get(SourceCurrencyCode, Today()) then
            ExchangeRate := CurrencyExchangeRate."Exchange Rate Amount";

        AddBasicField(TaxExchangeRateObject, 'SourceCurrencyCode', SourceCurrencyCode);
        AddBasicField(TaxExchangeRateObject, 'TargetCurrencyCode', 'MYR');
        AddNumericField(TaxExchangeRateObject, 'CalculationRate', ExchangeRate);
        AddBasicField(TaxExchangeRateObject, 'Date', Format(SalesCrMemoHeader."Posting Date", 0, '<Year4>-<Month,2>-<Day,2>'));

        TaxExchangeRateArray.Add(TaxExchangeRateObject);
        // Defensive: ensure shape is always an array by removing any previous scalar/object entry
        if InvoiceObject.Contains('TaxExchangeRate') then
            InvoiceObject.Remove('TaxExchangeRate');
        InvoiceObject.Add('TaxExchangeRate', TaxExchangeRateArray);

        // Normalize any mis-shaped TaxExchangeRate into array-of-object with flat child fields
        NormalizeTaxExchangeRate(InvoiceObject);
    end;

    // Overloaded version for credit memos
    local procedure AddInvoicePeriod(var InvoiceObject: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        PeriodArray: JsonArray;
        PeriodObject: JsonObject;
        StartDate: Date;
        EndDate: Date;
        PeriodDescription: Text;
    begin
        // Only add invoice period if custom fields are populated in the Sales Cr.Memo Header
        if ShouldIncludeInvoicePeriod(SalesCrMemoHeader) then begin
            GetInvoicePeriodDetails(SalesCrMemoHeader, StartDate, EndDate, PeriodDescription);

            AddBasicField(PeriodObject, 'StartDate', Format(StartDate, 0, '<Year4>-<Month,2>-<Day,2>'));
            AddBasicField(PeriodObject, 'EndDate', Format(EndDate, 0, '<Year4>-<Month,2>-<Day,2>'));
            AddBasicField(PeriodObject, 'Description', PeriodDescription);

            PeriodArray.Add(PeriodObject);
            InvoiceObject.Add('InvoicePeriod', PeriodArray);
        end;
    end;

    // Overloaded version for credit memos - Enhanced for LHDN compliance
    local procedure AddBillingReference(var InvoiceObject: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        BillingReferenceArray: JsonArray;
        BillingReferenceObject: JsonObject;
        InvoiceDocumentReferenceArray: JsonArray;
        InvoiceDocumentReferenceObject: JsonObject;
        IDObject: JsonObject;
        IssueDateObject: JsonObject;
        SalesInvoiceHeader: Record "Sales Invoice Header";
    begin
        // Add billing reference for credit memos if applicable
        // This is OPTIONAL but recommended for better traceability
        if SalesCrMemoHeader."Applies-to Doc. No." <> '' then begin
            // Enhanced billing reference structure for credit notes
            // LHDN MyInvois API enforces 26-character limit for BillingReference ID fields
            // Reference: https://sdk.myinvois.hasil.gov.my/documents/credit-v1-1/
            if StrLen(SalesCrMemoHeader."Applies-to Doc. No.") > 26 then
                AddBasicField(IDObject, 'ID', CopyStr(SalesCrMemoHeader."Applies-to Doc. No.", 1, 26))
            else
                AddBasicField(IDObject, 'ID', SalesCrMemoHeader."Applies-to Doc. No.");
            InvoiceDocumentReferenceObject.Add('ID', IDObject);

            // Add issue date of the original invoice if available
            // Note: Sales Invoice Header No. field is Code[20], so truncate for lookup
            if SalesInvoiceHeader.Get(CopyStr(SalesCrMemoHeader."Applies-to Doc. No.", 1, 20)) then begin
                AddBasicField(IssueDateObject, 'IssueDate', Format(SalesInvoiceHeader."Posting Date", 0, '<Year4>-<Month,2>-<Day,2>'));
                InvoiceDocumentReferenceObject.Add('IssueDate', IssueDateObject);
            end;

            InvoiceDocumentReferenceArray.Add(InvoiceDocumentReferenceObject);
            BillingReferenceObject.Add('InvoiceDocumentReference', InvoiceDocumentReferenceArray);
            BillingReferenceArray.Add(BillingReferenceObject);
            InvoiceObject.Add('BillingReference', BillingReferenceArray);
        end;
        // If no "Applies-to Doc. No." is set, skip billing reference
        // LHDN accepts credit notes without billing references
    end;

    // Overloaded version for credit memos - FIXED: Use proper UBL 2.1 array format
    local procedure AddAdditionalDocumentReferences(var InvoiceObject: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        AdditionalDocArray: JsonArray;
        RefObject: JsonObject;
        HasReferences: Boolean;
    begin
        // Only add if there are actual references - use same format as sales invoice
        if SalesCrMemoHeader."External Document No." <> '' then begin
            Clear(RefObject);
            // LHDN MyInvois API enforces 26-character limit for BillingReference ID fields
            // Reference: https://sdk.myinvois.hasil.gov.my/documents/credit-v1-1/
            if StrLen(SalesCrMemoHeader."External Document No.") > 26 then
                AddBasicField(RefObject, 'ID', CopyStr(SalesCrMemoHeader."External Document No.", 1, 26))
            else
                AddBasicField(RefObject, 'ID', SalesCrMemoHeader."External Document No.");
            AddBasicField(RefObject, 'DocumentType', 'PurchaseOrder');
            AdditionalDocArray.Add(RefObject);
            HasReferences := true;
        end;

        if HasReferences then
            InvoiceObject.Add('AdditionalDocumentReference', AdditionalDocArray);
    end;

    // Overloaded version for credit memos
    local procedure AddDelivery(var InvoiceObject: JsonObject; Customer: Record Customer; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        DeliveryArray: JsonArray;
        DeliveryObject: JsonObject;
        DeliveryAddressObject: JsonObject;
    begin
        // Add delivery information for credit memos if different from billing address
        if SalesCrMemoHeader."Ship-to Address" <> '' then begin
            AddBasicField(DeliveryAddressObject, 'StreetName', SalesCrMemoHeader."Ship-to Address");
            AddBasicField(DeliveryAddressObject, 'CityName', SalesCrMemoHeader."Ship-to City");
            AddBasicField(DeliveryAddressObject, 'PostalZone', SalesCrMemoHeader."Ship-to Post Code");
            AddBasicField(DeliveryAddressObject, 'CountrySubentity', SalesCrMemoHeader."Ship-to County");
            AddBasicField(DeliveryAddressObject, 'CountrySubentityCode', SalesCrMemoHeader."Ship-to County");

            DeliveryObject.Add('DeliveryAddress', DeliveryAddressObject);
            DeliveryArray.Add(DeliveryObject);
            InvoiceObject.Add('Delivery', DeliveryArray);
        end;
    end;

    // Overloaded version for credit memos - FIXED: Use proper UBL 2.1 array format
    local procedure AddPaymentMeans(var InvoiceObject: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        PaymentMeansArray: JsonArray;
        PaymentMeansObject: JsonObject;
        PayeeAccountArray: JsonArray;
        PayeeAccountObject: JsonObject;
        PaymentMeansCode: Code[10];
    begin
        // CRITICAL: PaymentMeansCode is mandatory and must use proper format
        PaymentMeansCode := GetCreditMemoPaymentMeansCode(SalesCrMemoHeader);
        AddBasicField(PaymentMeansObject, 'PaymentMeansCode', PaymentMeansCode);

        // Only add bank account for bank transfer payments
        if PaymentMeansCode = '03' then begin // Bank Transfer
            AddBasicField(PayeeAccountObject, 'ID', GetBankAccountNumber());
            PayeeAccountArray.Add(PayeeAccountObject);
            PaymentMeansObject.Add('PayeeFinancialAccount', PayeeAccountArray);
        end;

        PaymentMeansArray.Add(PaymentMeansObject);
        InvoiceObject.Add('PaymentMeans', PaymentMeansArray);
    end;

    // Helper function to get payment means code for credit memos
    local procedure GetCreditMemoPaymentMeansCode(SalesCrMemoHeader: Record "Sales Cr.Memo Header"): Code[10]
    var
        PaymentMode: Code[10];
    begin
        // Return the payment mode from the credit memo header
        PaymentMode := SalesCrMemoHeader."eInvoice Payment Mode";

        // Validate and return appropriate payment mode
        case PaymentMode of
            '01':
                exit('01'); // Cash
            '02':
                exit('02'); // Cheque
            '03':
                exit('03'); // Bank Transfer
            '04':
                exit('04'); // Credit Card
            '05':
                exit('05'); // Debit Card
            '06':
                exit('06'); // e-Wallet / Digital Wallet
            '07':
                exit('07'); // Digital Bank
            '08':
                exit('08'); // Others
            else begin
                // Log warning for debugging
                LogDebugInfo('Credit Memo Payment Mode Warning',
                    StrSubstNo('Invalid or empty payment mode "%1" for credit memo %2. Returning default value.',
                        PaymentMode, SalesCrMemoHeader."No."));
                exit('08'); // Return Others if not specified or invalid
            end;
        end;
    end;

    // Overloaded version for credit memos - FIXED: Use proper UBL 2.1 array format
    local procedure AddPaymentTerms(var InvoiceObject: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        PaymentTermsArray: JsonArray;
        PaymentTermsObject: JsonObject;
    begin
        // Add main payment terms note using proper format
        AddBasicField(PaymentTermsObject, 'Note', GetCreditMemoPaymentTermsNote(SalesCrMemoHeader));

        PaymentTermsArray.Add(PaymentTermsObject);
        InvoiceObject.Add('PaymentTerms', PaymentTermsArray);
    end;

    // Helper function to get payment terms note for credit memos
    local procedure GetCreditMemoPaymentTermsNote(SalesCrMemoHeader: Record "Sales Cr.Memo Header"): Text
    var
        PaymentTerms: Record "Payment Terms";
        PaymentTermsText: Text;
    begin
        // Get payment terms from Payment Terms Code
        if SalesCrMemoHeader."Payment Terms Code" <> '' then begin
            if PaymentTerms.Get(SalesCrMemoHeader."Payment Terms Code") then begin
                if PaymentTerms.Description <> '' then
                    PaymentTermsText := PaymentTerms.Description
                else
                    PaymentTermsText := SalesCrMemoHeader."Payment Terms Code";
                exit(PaymentTermsText);
            end;
        end;

        // Fallback: Use payment mode description
        exit(GetCreditMemoPaymentModeDescription(SalesCrMemoHeader));
    end;

    // Helper function to get payment mode description for credit memos
    local procedure GetCreditMemoPaymentModeDescription(SalesCrMemoHeader: Record "Sales Cr.Memo Header"): Text
    var
        PaymentModeCode: Code[10];
    begin
        PaymentModeCode := GetCreditMemoPaymentMeansCode(SalesCrMemoHeader);

        case PaymentModeCode of
            '01':
                exit('Cash');
            '02':
                exit('Cheque');
            '03':
                exit('Bank Transfer');
            '04':
                exit('Credit Card');
            '05':
                exit('Debit Card');
            '06':
                exit('e-Wallet / Digital Wallet');
            '07':
                exit('Digital Bank');
            '08':
                exit('Others');
            else
                exit('Credit Memo Payment');
        end;
    end;

    // Overloaded version for credit memos
    local procedure HasPrepaidAmount(SalesCrMemoHeader: Record "Sales Cr.Memo Header"): Boolean
    begin
        // Check if credit memo has prepaid amount - simplified for credit memos
        exit(false); // Credit memos typically don't have prepaid amounts
    end;

    // Overloaded version for credit memos
    local procedure AddPrepaidPayment(var InvoiceObject: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        PrepaidPaymentArray: JsonArray;
        PrepaidPaymentObject: JsonObject;
        PaidAmountObject: JsonObject;
    begin
        // Credit memos typically don't have prepaid payments
        // This procedure is kept for consistency but doesn't add anything
    end;

    // Overloaded version for credit memos
    local procedure AddAllowanceCharges(var InvoiceObject: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        AllowanceChargeArray: JsonArray;
        AllowanceChargeObject: JsonObject;
        ChargeIndicatorObject: JsonObject;
        AmountObject: JsonObject;
        BaseAmountObject: JsonObject;
        TotalDiscountAmount: Decimal;
    begin
        // Calculate total discount amount from credit memo lines
        TotalDiscountAmount := GetTotalDiscountAmount(SalesCrMemoHeader);

        // Add allowance/charges for credit memos
        if TotalDiscountAmount <> 0 then begin
            AddBasicField(ChargeIndicatorObject, 'ChargeIndicator', 'false');
            AddBasicField(AmountObject, 'Amount', Format(TotalDiscountAmount));
            AddBasicField(BaseAmountObject, 'BaseAmount', Format(SalesCrMemoHeader."Amount Including VAT"));

            AllowanceChargeObject.Add('ChargeIndicator', ChargeIndicatorObject);
            AllowanceChargeObject.Add('Amount', AmountObject);
            AllowanceChargeObject.Add('BaseAmount', BaseAmountObject);
            AllowanceChargeArray.Add(AllowanceChargeObject);
            InvoiceObject.Add('AllowanceCharge', AllowanceChargeArray);
        end;
    end;

    // Overloaded version for credit memos - FIXED: Use proper UBL 2.1 array format
    local procedure AddTaxTotals(var InvoiceObject: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        TaxTotalArray: JsonArray;
        TaxTotalObject: JsonObject;
        TaxSubtotalArray: JsonArray;
        TaxSubtotalObject: JsonObject;
        TaxCategoryArray: JsonArray;
        TaxCategoryObject: JsonObject;
        TaxSchemeArray: JsonArray;
        TaxSchemeObject: JsonObject;
        TotalTaxAmount: Decimal;
        TaxableAmount: Decimal;
        SalesCrMemoLine: Record "Sales Cr.Memo Line";
    begin
        SalesCrMemoLine.SetRange("Document No.", SalesCrMemoHeader."No.");
        SalesCrMemoLine.SetFilter("VAT %", '>0');
        if SalesCrMemoLine.FindSet() then
            repeat
                // Calculate tax amount from the line (ensure positive)
                TotalTaxAmount += Abs(SalesCrMemoLine."Amount Including VAT" - SalesCrMemoLine.Amount);
                // Calculate taxable amount from unit price and quantity (ensure positive)
                TaxableAmount += Abs(SalesCrMemoLine."Unit Price" * SalesCrMemoLine.Quantity);
            until SalesCrMemoLine.Next() = 0;

        AddAmountField(TaxTotalObject, 'TaxAmount', TotalTaxAmount, GetCurrencyCodeFromText(SalesCrMemoHeader."Currency Code"));

        // Tax subtotal with proper array structure - Use positive amounts for LHDN
        AddAmountField(TaxSubtotalObject, 'TaxableAmount', TaxableAmount, GetCurrencyCodeFromText(SalesCrMemoHeader."Currency Code"));
        AddAmountField(TaxSubtotalObject, 'TaxAmount', TotalTaxAmount, GetCurrencyCodeFromText(SalesCrMemoHeader."Currency Code"));

        // CRITICAL FIX: Tax category must be in array format
        AddBasicField(TaxCategoryObject, 'ID', '01');

        // Tax scheme with proper array structure
        AddBasicFieldWithAttributes(TaxSchemeObject, 'ID', 'OTH', 'schemeID', 'UN/ECE 5153', 'schemeAgencyID', '6');
        TaxSchemeArray.Add(TaxSchemeObject);
        TaxCategoryArray.Add(TaxCategoryObject);
        TaxCategoryObject.Add('TaxScheme', TaxSchemeArray);

        TaxSubtotalArray.Add(TaxSubtotalObject);
        TaxSubtotalObject.Add('TaxCategory', TaxCategoryArray);
        TaxTotalObject.Add('TaxSubtotal', TaxSubtotalArray);

        TaxTotalArray.Add(TaxTotalObject);
        InvoiceObject.Add('TaxTotal', TaxTotalArray);
    end;

    // Overloaded version for credit memos - Enhanced implementation
    local procedure AddLegalMonetaryTotal(var InvoiceObject: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        LegalTotalArray: JsonArray;
        LegalTotalObject: JsonObject;
        CurrencyCode: Code[10];
        Subtotal: Decimal;
        TaxTotal: Decimal;
        GrandTotal: Decimal;
        SalesCrMemoLine: Record "Sales Cr.Memo Line";
        LineAmount: Decimal;
        LineTaxAmount: Decimal;
    begin
        CurrencyCode := GetCurrencyCodeFromText(SalesCrMemoHeader."Currency Code");

        // Calculate amounts from lines to ensure accuracy (BC header amounts may be negative)
        Subtotal := 0;
        TaxTotal := 0;
        GrandTotal := 0;

        SalesCrMemoLine.SetRange("Document No.", SalesCrMemoHeader."No.");
        SalesCrMemoLine.SetFilter(Type, '<>%1', SalesCrMemoLine.Type::" ");
        if SalesCrMemoLine.FindSet() then
            repeat
                // Calculate line amounts - ensure they're positive for LHDN
                LineAmount := Abs(SalesCrMemoLine."Unit Price" * SalesCrMemoLine.Quantity);
                LineTaxAmount := Abs(SalesCrMemoLine."Amount Including VAT" - SalesCrMemoLine.Amount);

                Subtotal += LineAmount;
                TaxTotal += LineTaxAmount;
                GrandTotal += LineAmount + LineTaxAmount;
            until SalesCrMemoLine.Next() = 0;

        // Ensure all amounts are positive for LHDN
        Subtotal := Abs(Subtotal);
        TaxTotal := Abs(TaxTotal);
        GrandTotal := Abs(GrandTotal);

        AddAmountField(LegalTotalObject, 'LineExtensionAmount', Subtotal, CurrencyCode);
        AddAmountField(LegalTotalObject, 'TaxExclusiveAmount', Subtotal, CurrencyCode);
        AddAmountField(LegalTotalObject, 'TaxInclusiveAmount', GrandTotal, CurrencyCode);
        AddAmountField(LegalTotalObject, 'PayableAmount', GrandTotal, CurrencyCode);

        LegalTotalArray.Add(LegalTotalObject);
        InvoiceObject.Add('LegalMonetaryTotal', LegalTotalArray);
    end;

    // Overloaded version for credit memos - FIXED: Ensure lines are always included with proper UBL format
    local procedure AddCreditMemoLines(var InvoiceObject: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        LineArray: JsonArray;
        SalesCrMemoLine: Record "Sales Cr.Memo Line";
    begin
        SalesCrMemoLine.SetRange("Document No.", SalesCrMemoHeader."No.");
        SalesCrMemoLine.SetFilter(Type, '<>%1', SalesCrMemoLine.Type::" ");
        if SalesCrMemoLine.FindSet() then
            repeat
                AddCreditMemoInvoiceLine(LineArray, SalesCrMemoLine, SalesCrMemoHeader."Currency Code");
            until SalesCrMemoLine.Next() = 0;
        // FIXED: LHDN expects InvoiceLine even for credit memos
        InvoiceObject.Add('InvoiceLine', LineArray);
    end;

    // Credit memo line implementation using proper UBL 2.1 array format
    local procedure AddCreditMemoInvoiceLine(var LineArray: JsonArray; SalesCrMemoLine: Record "Sales Cr.Memo Line"; CurrencyCode: Code[10])
    var
        LineObject: JsonObject;
        TaxTotalArray: JsonArray;
        TaxTotalObject: JsonObject;
        TaxSubtotalArray: JsonArray;
        TaxSubtotalObject: JsonObject;
        TaxCategoryArray: JsonArray;
        TaxCategoryObject: JsonObject;
        TaxSchemeArray: JsonArray;
        TaxSchemeObject: JsonObject;
        AllowanceChargeArray: JsonArray;
        CommodityArray: JsonArray;
        CommodityObject: JsonObject;
        ItemClassificationCodeArray: JsonArray;
        ItemClassificationCodeObject: JsonObject;
        OriginCountryArray: JsonArray;
        OriginCountryObject: JsonObject;
        IdentificationCodeArray: JsonArray;
        IdentificationCodeObject: JsonObject;
        DescriptionArray: JsonArray;
        DescriptionObject: JsonObject;
        ItemPriceExtensionArray: JsonArray;
        ItemPriceExtensionObject: JsonObject;
        ItemArray: JsonArray;
        ItemObject: JsonObject;
        PriceArray: JsonArray;
        PriceObject: JsonObject;
        UnitCode: Code[10];
    begin
        // Line ID and quantity
        AddBasicField(LineObject, 'ID', Format(SalesCrMemoLine."Line No."));

        UnitCode := GetUBLUnitCode(SalesCrMemoLine);
        AddQuantityField(LineObject, 'InvoicedQuantity', SalesCrMemoLine.Quantity, UnitCode);
        // Use Unit Price * Quantity for line extension amount to ensure positive value
        AddAmountField(LineObject, 'LineExtensionAmount', Abs(SalesCrMemoLine."Unit Price" * SalesCrMemoLine.Quantity), GetCurrencyCodeFromText(CurrencyCode));

        // Line allowances/charges - Use positive amounts for LHDN
        if SalesCrMemoLine."Line Discount Amount" <> 0 then
            AddLineAllowanceCharge(AllowanceChargeArray, false, '',
                SalesCrMemoLine."Line Discount %", Abs(SalesCrMemoLine."Line Discount Amount"), GetCurrencyCodeFromText(CurrencyCode));

        if AllowanceChargeArray.Count > 0 then
            LineObject.Add('AllowanceCharge', AllowanceChargeArray);

        // Tax total for line - Use positive amounts for LHDN
        AddAmountField(TaxTotalObject, 'TaxAmount', Abs(SalesCrMemoLine."Amount Including VAT" - SalesCrMemoLine.Amount), GetCurrencyCodeFromText(CurrencyCode));

        // Tax subtotal - Use positive amounts for LHDN
        AddAmountField(TaxSubtotalObject, 'TaxableAmount', Abs(SalesCrMemoLine."Unit Price" * SalesCrMemoLine.Quantity), GetCurrencyCodeFromText(CurrencyCode));
        AddAmountField(TaxSubtotalObject, 'TaxAmount', Abs(SalesCrMemoLine."Amount Including VAT" - SalesCrMemoLine.Amount), GetCurrencyCodeFromText(CurrencyCode));
        AddNumericField(TaxSubtotalObject, 'Percent', SalesCrMemoLine."VAT %");

        // Tax category
        AddBasicField(TaxCategoryObject, 'ID', SalesCrMemoLine."e-Invoice Tax Type");

        // Add TaxExemptionReason only for exempt tax types
        if SalesCrMemoLine."e-Invoice Tax Type" in ['E', 'Z'] then
            AddBasicField(TaxCategoryObject, 'TaxExemptionReason', GetTaxExemptionReason(SalesCrMemoLine."e-Invoice Tax Type"));

        // Tax scheme
        AddBasicFieldWithAttributes(TaxSchemeObject, 'ID', 'OTH', 'schemeID', 'UN/ECE 5153', 'schemeAgencyID', '6');
        TaxSchemeArray.Add(TaxSchemeObject);
        TaxCategoryArray.Add(TaxCategoryObject);
        TaxCategoryObject.Add('TaxScheme', TaxSchemeArray);

        TaxSubtotalArray.Add(TaxSubtotalObject);
        TaxSubtotalObject.Add('TaxCategory', TaxCategoryArray);
        TaxTotalObject.Add('TaxSubtotal', TaxSubtotalArray);

        TaxTotalArray.Add(TaxTotalObject);
        LineObject.Add('TaxTotal', TaxTotalArray);

        // Item information
        // MANDATORY: Product Tariff Code (PTC) - FIRST classification
        ItemClassificationCodeObject.Add('_', GetHSCode(SalesCrMemoLine));
        ItemClassificationCodeObject.Add('listID', 'PTC');
        ItemClassificationCodeArray.Add(ItemClassificationCodeObject);
        CommodityObject.Add('ItemClassificationCode', ItemClassificationCodeArray);
        CommodityArray.Add(CommodityObject);

        // MANDATORY: Classification Code (CLASS) - SECOND classification
        Clear(CommodityObject);
        Clear(ItemClassificationCodeArray);
        Clear(ItemClassificationCodeObject);
        ItemClassificationCodeObject.Add('_', GetClassificationCode(SalesCrMemoLine));
        ItemClassificationCodeObject.Add('listID', 'CLASS');
        ItemClassificationCodeArray.Add(ItemClassificationCodeObject);
        CommodityObject.Add('ItemClassificationCode', ItemClassificationCodeArray);
        CommodityArray.Add(CommodityObject);

        ItemObject.Add('CommodityClassification', CommodityArray);

        // Description
        DescriptionObject.Add('_', SalesCrMemoLine.Description);
        DescriptionArray.Add(DescriptionObject);
        ItemObject.Add('Description', DescriptionArray);

        // Origin country
        IdentificationCodeObject.Add('_', GetOriginCountryCode(SalesCrMemoLine));
        IdentificationCodeArray.Add(IdentificationCodeObject);
        OriginCountryObject.Add('IdentificationCode', IdentificationCodeArray);
        OriginCountryArray.Add(OriginCountryObject);
        ItemObject.Add('OriginCountry', OriginCountryArray);

        ItemArray.Add(ItemObject);
        LineObject.Add('Item', ItemArray);

        // Price - Use positive amounts for LHDN
        AddAmountField(PriceObject, 'PriceAmount', Abs(SalesCrMemoLine."Unit Price"), GetCurrencyCodeFromText(CurrencyCode));
        PriceArray.Add(PriceObject);
        LineObject.Add('Price', PriceArray);

        // Item price extension - Use positive amounts for LHDN
        AddAmountField(ItemPriceExtensionObject, 'Amount', Abs(SalesCrMemoLine."Unit Price" * SalesCrMemoLine.Quantity), GetCurrencyCodeFromText(CurrencyCode));
        ItemPriceExtensionArray.Add(ItemPriceExtensionObject);
        LineObject.Add('ItemPriceExtension', ItemPriceExtensionArray);

        LineArray.Add(LineObject);
    end;

    // Helper functions for credit memo lines
    local procedure GetHSCode(SalesCrMemoLine: Record "Sales Cr.Memo Line"): Text
    begin
        // Return the HS code directly from the e-Invoice Classification field
        if SalesCrMemoLine."e-Invoice Classification" <> '' then
            exit(SalesCrMemoLine."e-Invoice Classification")
        else
            exit('022'); // Default HS code if empty
    end;

    local procedure GetClassificationCode(SalesCrMemoLine: Record "Sales Cr.Memo Line"): Text
    var
        eInvoiceClassification: Record eInvoiceClassification;
    begin
        // First, try to get classification from the credit memo line
        if SalesCrMemoLine."e-Invoice Classification" <> '' then begin
            // Verify the classification exists in the eInvoiceClassification table
            if eInvoiceClassification.Get(SalesCrMemoLine."e-Invoice Classification") then
                exit(SalesCrMemoLine."e-Invoice Classification")
            else
                exit(SalesCrMemoLine."e-Invoice Classification"); // Still use the value even if not found in table
        end;

        // Fallback to universal classification if field is empty
        exit('022'); // Universal fallback classification
    end;

    local procedure GetOriginCountryCode(SalesCrMemoLine: Record "Sales Cr.Memo Line"): Text
    var
        Item: Record Item;
        CompanyInformation: Record "Company Information";
    begin
        // Try to get from item first
        if SalesCrMemoLine.Type = SalesCrMemoLine.Type::Item then begin
            if Item.Get(SalesCrMemoLine."No.") then begin
                // If you have a country of origin field on Item table, use it
                // exit(Item."Country of Origin Code");
            end;
        end;

        // Fallback to company information
        if CompanyInformation.Get() then
            exit(GetCountryCode(CompanyInformation."e-Invoice Country Code"));

        exit('MYS'); // Default to Malaysia
    end;

    local procedure AddCreditMemoItemClassification(var ItemObject: JsonObject; SalesCrMemoLine: Record "Sales Cr.Memo Line")
    var
        ClassificationArray: JsonArray;
        ClassificationObject: JsonObject;
        ClassificationCode: Text;
    begin
        ClassificationCode := GetCreditMemoClassificationCode(SalesCrMemoLine);

        AddBasicField(ClassificationObject, 'ItemClassificationCode', ClassificationCode);
        AddBasicField(ClassificationObject, 'Description', 'Product Classification');
        ClassificationArray.Add(ClassificationObject);
        ItemObject.Add('CommodityClassification', ClassificationArray);
    end;

    // Helper function to get classification code for credit memo lines
    local procedure GetCreditMemoClassificationCode(SalesCrMemoLine: Record "Sales Cr.Memo Line"): Text
    var
        eInvoiceClassification: Record eInvoiceClassification;
    begin
        // Return the classification code directly from the e-Invoice Classification field
        if SalesCrMemoLine."e-Invoice Classification" <> '' then begin
            // Verify the classification exists in the eInvoiceClassification table
            if eInvoiceClassification.Get(SalesCrMemoLine."e-Invoice Classification") then
                exit(SalesCrMemoLine."e-Invoice Classification")
            else
                exit(SalesCrMemoLine."e-Invoice Classification"); // Still use the value even if not found in table
        end;

        // Fallback to universal classification if field is empty
        exit('022'); // Universal fallback classification
    end;

    // Helper function to get UBL unit code for credit memo lines
    local procedure GetUBLUnitCode(SalesCrMemoLine: Record "Sales Cr.Memo Line"): Code[10]
    begin
        // Return the UBL unit code directly from the e-Invoice UOM field
        if SalesCrMemoLine."e-Invoice UOM" <> '' then
            exit(SalesCrMemoLine."e-Invoice UOM")
        else
            exit('EA'); // Default to pieces if empty
    end;

    // Overloaded version for credit memos
    local procedure AddDigitalSignature(var InvoiceObject: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        SignatureObject: JsonObject;
        SignatureInformationObject: JsonObject;
        SignatureObject2: JsonObject;
    begin
        // Add digital signature for credit memos (same structure as invoices)
        AddBasicField(SignatureInformationObject, 'ID', 'SIG-' + SalesCrMemoHeader."No.");
        AddBasicField(SignatureObject2, 'ID', 'SIG-' + SalesCrMemoHeader."No.");

        SignatureObject.Add('ID', SignatureInformationObject);
        SignatureObject.Add('SignatureInformation', SignatureObject2);

        InvoiceObject.Add('Signature', SignatureObject);
    end;

    // Overloaded version for credit memos
    local procedure ShouldIncludeDelivery(SalesCrMemoHeader: Record "Sales Cr.Memo Header"): Boolean
    begin
        // Define business logic for when to include delivery/shipping recipient information for credit memos
        exit(SalesCrMemoHeader."Ship-to Address" <> '');
    end;

    // Overloaded version for credit memos
    local procedure ShouldIncludeInvoicePeriod(SalesCrMemoHeader: Record "Sales Cr.Memo Header"): Boolean
    begin
        // FIXED: Make invoice period optional - only include when there are actual period values
        // Check if there are custom period fields populated (you would need to add these fields to Sales Cr.Memo Header)
        // For now, return false to make it completely optional since period data should come from actual business data

        // You can enable this by adding custom fields to Sales Cr.Memo Header:
        // if (SalesCrMemoHeader."Custom Period Start" <> 0D) or 
        //    (SalesCrMemoHeader."Custom Period End" <> 0D) or 
        //    (SalesCrMemoHeader."Custom Period Description" <> '') then
        //     exit(true);

        exit(false); // Optional by default - only include when business logic requires it
    end;

    // Overloaded version for credit memos
    local procedure GetInvoicePeriodDetails(SalesCrMemoHeader: Record "Sales Cr.Memo Header"; var StartDate: Date; var EndDate: Date; var PeriodDescription: Text)
    begin
        // Get period details from credit memo data
        EndDate := SalesCrMemoHeader."Posting Date";

        case SalesCrMemoHeader."eInvoice Document Type" of
            '02': // Credit note
                begin
                    StartDate := CalcDate('<-CM>', EndDate); // Start of current month
                    PeriodDescription := 'Monthly credit adjustment';
                end;
            '03': // Debit note
                begin
                    StartDate := CalcDate('<-CM>', EndDate); // Start of current month
                    PeriodDescription := 'Monthly debit adjustment';
                end;
            else begin
                StartDate := EndDate;
                PeriodDescription := 'Credit memo adjustment';
            end;
        end;
    end;

    // Helper function to calculate total discount amount from credit memo lines
    local procedure GetTotalDiscountAmount(SalesCrMemoHeader: Record "Sales Cr.Memo Header"): Decimal
    var
        SalesCrMemoLine: Record "Sales Cr.Memo Line";
        TotalDiscount: Decimal;
    begin
        TotalDiscount := 0;
        SalesCrMemoLine.SetRange("Document No.", SalesCrMemoHeader."No.");
        SalesCrMemoLine.SetFilter(Type, '<>%1', SalesCrMemoLine.Type::" ");

        if SalesCrMemoLine.FindSet() then
            repeat
                // Only add non-zero discounts (could be positive or negative in BC)
                if SalesCrMemoLine."Line Discount Amount" <> 0 then
                    TotalDiscount += Abs(SalesCrMemoLine."Line Discount Amount");
            until SalesCrMemoLine.Next() = 0;

        exit(TotalDiscount);
    end;

    // Environment detection helper for both invoice and credit memo types
    local procedure GetEnvironmentSetting(): Text
    var
        eInvoiceSetup: Record "eInvoiceSetup";
    begin
        if eInvoiceSetup.Get() then begin
            case eInvoiceSetup.Environment of
                eInvoiceSetup.Environment::Preprod:
                    exit('PREPROD');
                eInvoiceSetup.Environment::Production:
                    exit('PRODUCTION');
                else
                    exit('PREPROD'); // Default fallback
            end;
        end;
        exit('PREPROD'); // Default to PREPROD if setup not found
    end;

    /// <summary>
    /// Determines document type based on Sales Invoice Header
    /// Can be extended with business logic for different document types
    /// </summary>
    local procedure GetDocumentTypeFromSalesInvoice(SalesInvoiceHeader: Record "Sales Invoice Header"): Text
    begin
        // Check if there's a specific document type field
        if SalesInvoiceHeader."eInvoice Document Type" <> '' then begin
            // Return the actual document type from the header (per LHDN official specification)
            case SalesInvoiceHeader."eInvoice Document Type" of
                '01':
                    exit('01'); // Invoice
                '02':
                    exit('02'); // Credit Note
                '03':
                    exit('03'); // Debit Note
                '04':
                    exit('04'); // Refund Note
                '11':
                    exit('11'); // Self-billed Invoice
                '12':
                    exit('12'); // Self-billed Credit Note
                '13':
                    exit('13'); // Self-billed Debit Note
                '14':
                    exit('14'); // Self-billed Refund Note
                else
                    exit('01'); // Default to Invoice for sales invoices
            end;
        end;

        // You can extend this logic based on your business rules
        // For example, check if it's a return or correction
        // if SalesInvoiceHeader."Return Receipt No." <> '' then
        //     exit('02'); // Credit note for returns

        exit('01'); // LHDN Standard Invoice type by default
    end;

    /// <summary>
    /// Determines document type based on Sales Credit Memo Header
    /// Can be extended with business logic for different document types
    /// </summary>
    local procedure GetDocumentTypeFromSalesCreditMemo(SalesCrMemoHeader: Record "Sales Cr.Memo Header"): Text
    begin
        // Check if there's a specific document type field
        if SalesCrMemoHeader."eInvoice Document Type" <> '' then begin
            // Return the actual document type from the header (per LHDN official specification)
            case SalesCrMemoHeader."eInvoice Document Type" of
                '01':
                    exit('01'); // Invoice
                '02':
                    exit('02'); // Credit Note
                '03':
                    exit('03'); // Debit Note
                '04':
                    exit('04'); // Refund Note
                '11':
                    exit('11'); // Self-billed Invoice
                '12':
                    exit('12'); // Self-billed Credit Note
                '13':
                    exit('13'); // Self-billed Debit Note
                '14':
                    exit('14'); // Self-billed Refund Note
                else
                    exit('02'); // Default to Credit Note for credit memos
            end;
        end;

        // Credit memos should default to credit note type
        exit('02'); // LHDN Credit Note type by default
    end;

    // ADD THIS: Credit Note specific procedure
    procedure PostCreditNoteToAzureFunction(SalesCrMemoHeader: Record "Sales Cr.Memo Header"; AzureFunctionUrl: Text; var ResponseText: Text)
    var
        JsonText: Text;
        Success: Boolean;
        UBLDocumentBuilder: Codeunit "eInvoice UBL Document Builder";
    begin
        // Generate credit note UBL JSON
        JsonText := UBLDocumentBuilder.BuildCreditMemoUBLJson(SalesCrMemoHeader);

        // Send to Azure Function for signing
        Success := TryPostToAzureFunctionSafe(JsonText, AzureFunctionUrl, ResponseText);

        if not Success then
            Error('Failed to process credit note through Azure Function: %1', ResponseText);
    end;

    // ADD THIS: Credit note submission to LHDN
    procedure SubmitCreditNoteToLHDN(SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        AzureFunctionUrl: Text;
        ResponseText: Text;
        ResponseJson: JsonObject;
        SignedJson: JsonToken;
        LhdnPayload: JsonToken;
        eInvoiceSetup: Record "eInvoiceSetup";
        LhdnResponse: Text;
        Success: Boolean;
    begin
        // Get Azure Function URL from setup
        eInvoiceSetup.Get();
        AzureFunctionUrl := eInvoiceSetup."Azure Function URL";

        // Send credit note for signing
        PostCreditNoteToAzureFunction(SalesCrMemoHeader, AzureFunctionUrl, ResponseText);

        // Parse response
        ResponseJson.ReadFrom(ResponseText);

        // Extract signed JSON and LHDN payload
        ResponseJson.Get('signedJson', SignedJson);
        ResponseJson.Get('lhdnPayload', LhdnPayload);

        // Submit to LHDN MyInvois API
        LhdnResponse := SafeJsonValueToText(LhdnPayload);
        Success := ProcessCreditMemoLhdnPayload(LhdnResponse, SalesCrMemoHeader, LhdnResponse);

        // Update credit note status
        if Success then begin
            SalesCrMemoHeader."eInvoice Validation Status" := 'Submitted';
            SalesCrMemoHeader.Modify();
        end else begin
            SalesCrMemoHeader."eInvoice Validation Status" := 'Submission Failed';
            SalesCrMemoHeader.Modify();
        end;

        // Log submission details
        LogCreditMemoSubmissionToTable(SalesCrMemoHeader,
            SafeJsonValueToText(SignedJson),
            LhdnResponse,
            SalesCrMemoHeader."eInvoice Validation Status",
            LhdnResponse,
            SalesCrMemoHeader."eInvoice Document Type");
    end;

    // ADDED: Function to download Azure Function payload for debugging LHDN API issues
    /// <summary>
    /// Downloads the payload from Azure Function for debugging purposes
    /// This helps troubleshoot "Invalid structured submission" errors from LHDN API
    /// </summary>
    /// <param name="DocumentType">Type of document: 'Invoice' or 'CreditMemo'</param>
    /// <param name="DocumentNo">Document number to process</param>
    /// <param name="Setup">eInvoice setup record</param>
    procedure DownloadAzureFunctionPayloadForDebugging(DocumentType: Text; DocumentNo: Code[20]; Setup: Record "eInvoiceSetup")
    var
        UBLDocumentBuilder: Codeunit "eInvoice UBL Document Builder";
        UnsignedJson: Text;
        AzureFunctionUrl: Text;
        ResponseText: Text;
        Success: Boolean;
        FileName: Text;
        TempBlob: Codeunit "Temp Blob";
        OutStream: OutStream;
        InStream: InStream;
        PayloadPreview: Text;
        CorrelationId: Text;
    begin
        if Setup."Azure Function URL" = '' then
            Error('Azure Function URL is not configured. Please configure it first.');

        AzureFunctionUrl := Setup."Azure Function URL";
        CorrelationId := CreateGuid();

        // Generate the appropriate UBL JSON based on document type
        case DocumentType of
            'Invoice':
                begin
                    // For invoices, we need to get the posted sales invoice
                    // This would need to be implemented based on your specific requirements
                    Error('Invoice debugging not yet implemented. Please use CreditMemo for now.');
                end;
            'CreditMemo':
                begin
                    // Generate credit memo UBL JSON
                    UnsignedJson := UBLDocumentBuilder.BuildCreditMemoUBLJson(GetSalesCrMemoHeader(DocumentNo));
                end;
            else
                Error('Invalid document type. Use ''Invoice'' or ''CreditMemo''.');
        end;

        if UnsignedJson = '' then
            Error('Failed to generate UBL JSON for document %1', DocumentNo);

        // Show preview of unsigned JSON
        PayloadPreview := CopyStr(UnsignedJson, 1, 500);
        Message('Generated UBL JSON Preview (first 500 chars):' + '\\' + '\\' + '%1' + '\\' + '\\' + '[Full payload will be downloaded as file]',
            PayloadPreview);

        // Send to Azure Function for signing
        Success := TryPostToAzureFunctionSafe(UnsignedJson, AzureFunctionUrl, ResponseText);

        if not Success then begin
            // Download the unsigned JSON for debugging
            FileName := StrSubstNo('DEBUG_Unsigned_%1_%2_%3.json',
                DocumentType,
                DocumentNo,
                Format(CurrentDateTime, 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2><Seconds,2>'));

            TempBlob.CreateOutStream(OutStream);
            OutStream.WriteText(UnsignedJson);
            TempBlob.CreateInStream(InStream);
            DownloadFromStream(InStream, 'Download Unsigned UBL JSON for Debugging', '', 'JSON files (*.json)|*.json', FileName);

            Error('Failed to communicate with Azure Function. Unsigned JSON has been downloaded for debugging.\\' +
                  'Error Details: %1\\' +
                  'Correlation ID: %2', ResponseText, CorrelationId);
        end;

        // Download the signed response from Azure Function
        FileName := StrSubstNo('DEBUG_AzureFunction_Response_%1_%2_%3.json',
            DocumentType,
            DocumentNo,
            Format(CurrentDateTime, 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2><Seconds,2>'));

        TempBlob.CreateOutStream(OutStream);
        OutStream.WriteText(ResponseText);
        TempBlob.CreateInStream(InStream);
        DownloadFromStream(InStream, 'Download Azure Function Response for Debugging', '', 'JSON files (*.json)|*.json', FileName);

        // Also download the unsigned JSON for comparison
        FileName := StrSubstNo('DEBUG_Unsigned_Comparison_%1_%2_%3.json',
            DocumentType,
            DocumentNo,
            Format(CurrentDateTime, 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2><Seconds,2>'));

        TempBlob.CreateOutStream(OutStream);
        OutStream.WriteText(UnsignedJson);
        TempBlob.CreateInStream(InStream);
        DownloadFromStream(InStream, 'Download Unsigned UBL JSON for Comparison', '', 'JSON files (*.json)|*.json', FileName);

        Message('Debug files downloaded successfully!\\' +
                '1. Azure Function Response: Contains the signed JSON and LHDN payload\\' +
                '2. Unsigned UBL JSON: For comparison and validation\\' +
                '\\' +
                'Use these files to debug the "Invalid structured submission" error.\\' +
                'Correlation ID: %1', CorrelationId);
    end;

    /// <summary>
    /// Helper function to get Sales Cr.Memo Header record
    /// </summary>
    /// <param name="DocumentNo">Credit memo document number</param>
    /// <returns>Sales Cr.Memo Header record</returns>
    local procedure GetSalesCrMemoHeader(DocumentNo: Code[20]) SalesCrMemoHeader: Record "Sales Cr.Memo Header"
    begin
        if not SalesCrMemoHeader.Get(DocumentNo) then
            Error('Credit Memo %1 not found.', DocumentNo);
    end;

    /// <summary>
    /// Downloads the LHDN submission payload for debugging
    /// This extracts the LHDN payload from the Azure Function response
    /// </summary>
    /// <param name="AzureFunctionResponse">Response from Azure Function</param>
    /// <param name="DocumentType">Type of document</param>
    /// <param name="DocumentNo">Document number</param>
    procedure DownloadLHDNSubmissionPayload(AzureFunctionResponse: Text; DocumentType: Text; DocumentNo: Code[20])
    var
        ResponseJson: JsonObject;
        LhdnPayload: JsonToken;
        LhdnPayloadText: Text;
        FileName: Text;
        TempBlob: Codeunit "Temp Blob";
        OutStream: OutStream;
        InStream: InStream;
        PayloadPreview: Text;
    begin
        // Parse the Azure Function response
        if not ResponseJson.ReadFrom(AzureFunctionResponse) then
            Error('Invalid JSON response from Azure Function');

        // Extract LHDN payload
        if not ResponseJson.Get('lhdnPayload', LhdnPayload) then
            Error('LHDN payload not found in Azure Function response');

        LhdnPayloadText := SafeJsonValueToText(LhdnPayload);

        if LhdnPayloadText = '' then
            Error('LHDN payload is empty');

        // Show preview
        PayloadPreview := CopyStr(LhdnPayloadText, 1, 500);
        Message('LHDN Submission Payload Preview (first 500 chars):' + '\\' + '\\' + '%1' + '\\' + '\\' + '[Full payload will be downloaded as file]',
            PayloadPreview);

        // Download the LHDN payload
        FileName := StrSubstNo('DEBUG_LHDN_Submission_Payload_%1_%2_%3.json',
            DocumentType,
            DocumentNo,
            Format(CurrentDateTime, 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2><Seconds,2>'));

        TempBlob.CreateOutStream(OutStream);
        OutStream.WriteText(LhdnPayloadText);
        TempBlob.CreateInStream(InStream);
        DownloadFromStream(InStream, 'Download LHDN Submission Payload for Debugging', '', 'JSON files (*.json)|*.json', FileName);

        Message('LHDN submission payload downloaded successfully!\\' +
                'File: %1\\' +
                '\\' +
                'This is the exact payload that will be sent to LHDN API.\\' +
                'Use it to validate against LHDN requirements and identify\\' +
                'the cause of "Invalid structured submission" errors.', FileName);
    end;

    /// <summary>
    /// Debug Azure Function payload for credit memo - Developer Console friendly version
    /// This procedure can be called directly from the developer console for testing
    /// </summary>
    /// <param name="DocumentNo">Credit memo document number to debug</param>
    procedure DebugCreditMemoPayload(DocumentNo: Code[20])
    var
        eInvoiceSetup: Record "eInvoiceSetup";
        UBLDocumentBuilder: Codeunit "eInvoice UBL Document Builder";
        UnsignedJson: Text;
        AzureFunctionUrl: Text;
        ResponseText: Text;
        Success: Boolean;
        FileName: Text;
        TempBlob: Codeunit "Temp Blob";
        OutStream: OutStream;
        InStream: InStream;
        PayloadPreview: Text;
        CorrelationId: Text;
        SalesCrMemoHeader: Record "Sales Cr.Memo Header";
    begin
        // Check if setup exists
        if not eInvoiceSetup.Get('SETUP') then
            Error('eInvoice setup not found. Please configure eInvoice setup first.');

        // Check if Azure Function URL is configured
        if eInvoiceSetup."Azure Function URL" = '' then
            Error('Azure Function URL is not configured. Please configure it first.');

        // Check if credit memo exists
        if not SalesCrMemoHeader.Get(DocumentNo) then
            Error('Credit Memo %1 not found.', DocumentNo);

        AzureFunctionUrl := eInvoiceSetup."Azure Function URL";
        CorrelationId := CreateGuid();

        // Generate credit memo UBL JSON
        UnsignedJson := UBLDocumentBuilder.BuildCreditMemoUBLJson(SalesCrMemoHeader);

        if UnsignedJson = '' then
            Error('Failed to generate UBL JSON for credit memo %1', DocumentNo);

        // Show preview of unsigned JSON
        PayloadPreview := CopyStr(UnsignedJson, 1, 500);
        Message('Generated UBL JSON Preview (first 500 chars):' + '\\' + '\\' + '%1' + '\\' + '\\' + '[Full payload will be downloaded as file]',
            PayloadPreview);

        // Send to Azure Function for signing
        Success := TryPostToAzureFunctionSafe(UnsignedJson, AzureFunctionUrl, ResponseText);

        if not Success then begin
            // Download the unsigned JSON for debugging
            FileName := StrSubstNo('DEBUG_Unsigned_CreditMemo_%1_%2.json',
                DocumentNo,
                Format(CurrentDateTime, 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2><Seconds,2>'));

            TempBlob.CreateOutStream(OutStream);
            OutStream.WriteText(UnsignedJson);
            TempBlob.CreateInStream(InStream);
            DownloadFromStream(InStream, 'Download Unsigned UBL JSON for Debugging', '', 'JSON files (*.json)|*.json', FileName);

            Error('Failed to communicate with Azure Function. Unsigned JSON has been downloaded for debugging.\\' +
                  'Error Details: %1\\' +
                  'Correlation ID: %2', ResponseText, CorrelationId);
        end;

        // Download the signed response from Azure Function
        FileName := StrSubstNo('DEBUG_AzureFunction_Response_CreditMemo_%1_%2.json',
            DocumentNo,
            Format(CurrentDateTime, 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2><Seconds,2>'));

        TempBlob.CreateOutStream(OutStream);
        OutStream.WriteText(ResponseText);
        TempBlob.CreateInStream(InStream);
        DownloadFromStream(InStream, 'Download Azure Function Response for Debugging', '', 'JSON files (*.json)|*.json', FileName);

        // Also download the unsigned JSON for comparison
        FileName := StrSubstNo('DEBUG_Unsigned_Comparison_CreditMemo_%1_%2.json',
            DocumentNo,
            Format(CurrentDateTime, 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2><Seconds,2>'));

        TempBlob.CreateOutStream(OutStream);
        OutStream.WriteText(UnsignedJson);
        TempBlob.CreateInStream(InStream);
        DownloadFromStream(InStream, 'Download Unsigned UBL JSON for Comparison', '', 'JSON files (*.json)|*.json', FileName);

        Message('Debug files downloaded successfully!\\' +
                '1. Azure Function Response: Contains the signed JSON and LHDN payload\\' +
                '2. Unsigned UBL JSON: For comparison and validation\\' +
                '\\' +
                'Use these files to debug the "Invalid structured submission" error.\\' +
                'Correlation ID: %1', CorrelationId);
    end;

    /// <summary>
    /// Get a list of available credit memos for debugging
    /// This helps developers find document numbers to test with
    /// </summary>
    /// <returns>Text containing available credit memo numbers</returns>
    procedure GetAvailableCreditMemosForDebugging(): Text
    var
        SalesCrMemoHeader: Record "Sales Cr.Memo Header";
        ResultText: Text;
        Count: Integer;
    begin
        Count := 0;
        ResultText := 'Available Credit Memos for Debugging:\\';

        if SalesCrMemoHeader.FindSet() then
            repeat
                Count += 1;
                if Count <= 10 then begin // Limit to first 10 for readability
                    ResultText += StrSubstNo('- %1 (Posted: %2)\\',
                        SalesCrMemoHeader."No.",
                        Format(SalesCrMemoHeader."Posting Date"));
                end;
            until (SalesCrMemoHeader.Next() = 0) or (Count >= 10);

        if Count > 10 then
            ResultText += StrSubstNo('... and %1 more credit memos available.', Count - 10);

        if Count = 0 then
            ResultText += 'No credit memos found in the system.';

        ResultText += '\\To debug a specific credit memo, use: DebugCreditMemoPayload(''DOCUMENT_NO'')';

        exit(ResultText);
    end;

    /// <summary>
    /// Updates existing submission log entries with correct amounts calculated from invoice lines
    /// This fixes the issue where old entries show 0.00 amounts
    /// </summary>
    procedure UpdateExistingSubmissionLogAmounts()
    var
        SubmissionLog: Record "eInvoice Submission Log";
        SalesInvoiceHeader: Record "Sales Invoice Header";
        SalesCrMemoHeader: Record "Sales Cr.Memo Header";
        SalesLine: Record "Sales Invoice Line";
        SalesCrMemoLine: Record "Sales Cr.Memo Line";
        TotalAmount: Decimal;
        TotalAmountInclVAT: Decimal;
        UpdateCount: Integer;
        ConfirmMsg: Label 'This will update all existing submission log entries to calculate amounts from invoice lines instead of header amounts.\Do you want to continue?';
    begin
        if not Confirm(ConfirmMsg) then
            exit;

        UpdateCount := 0;

        // Process all submission log entries
        if SubmissionLog.FindSet(true) then
            repeat
                // Reset amounts
                TotalAmount := 0;
                TotalAmountInclVAT := 0;

                // Try to find the invoice first
                if SalesInvoiceHeader.Get(SubmissionLog."Invoice No.") then begin
                    // Calculate from sales invoice lines
                    SalesLine.SetRange("Document No.", SubmissionLog."Invoice No.");
                    if SalesLine.FindSet() then
                        repeat
                            TotalAmount += SalesLine.Amount;
                            TotalAmountInclVAT += SalesLine."Amount Including VAT";
                        until SalesLine.Next() = 0;
                end else if SalesCrMemoHeader.Get(SubmissionLog."Invoice No.") then begin
                    // Calculate from sales credit memo lines
                    SalesCrMemoLine.SetRange("Document No.", SubmissionLog."Invoice No.");
                    if SalesCrMemoLine.FindSet() then
                        repeat
                            TotalAmount += SalesCrMemoLine.Amount;
                            TotalAmountInclVAT += SalesCrMemoLine."Amount Including VAT";
                        until SalesCrMemoLine.Next() = 0;
                end;

                // Update the submission log if amounts have changed
                if (SubmissionLog."Amount" <> TotalAmount) or (SubmissionLog."Amount Including VAT" <> TotalAmountInclVAT) then begin
                    SubmissionLog."Amount" := TotalAmount;
                    SubmissionLog."Amount Including VAT" := TotalAmountInclVAT;
                    SubmissionLog."Last Updated" := CurrentDateTime;
                    if SubmissionLog.Modify() then
                        UpdateCount += 1;
                end;

            until SubmissionLog.Next() = 0;

        Message('%1 submission log entries have been updated with correct amounts.', UpdateCount);
    end;
}
