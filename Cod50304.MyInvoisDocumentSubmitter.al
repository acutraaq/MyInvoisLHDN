codeunit 50304 "MyInvois DocumentSubmitter"
{
    procedure GenerateAndSubmitInvoice(SalesInvNo: Code[20]): Text
    var
        SalesInvHeader: Record "Sales Invoice Header";
        JsonBuilder: Codeunit "MyInvois Json Builder";
        InvoiceJson: JsonObject;
        InvoiceText, SubmitResponse : Text;
    begin
        // Get invoice record
        if not SalesInvHeader.Get(SalesInvNo) then
            Error('Sales Invoice %1 not found.', SalesInvNo);

        // Build raw invoice JSON
        InvoiceJson := JsonBuilder.BuildInvoiceJson(SalesInvHeader);
        InvoiceJson.WriteTo(InvoiceText);

        // Directly submit without external signing
        SubmitResponse := SubmitSignedDocumentBatch(SalesInvNo, InvoiceText);
        exit(SubmitResponse);
    end;

    procedure SubmitSignedDocumentBatch(InternalId: Code[20]; SignedJsonText: Text): Text
    var
        MyInvoisSetup: Record "MyInvoisSetup";
        TokenHelper: Codeunit "MyInvoisHelper";
        SalesInvHeader: Record "Sales Invoice Header";
        HttpClient: HttpClient;
        RequestContent: HttpContent;
        Response: HttpResponseMessage;
        Headers: HttpHeaders;
        ResponseText: Text;
        Token: Text;
        RootJson, DocJson, ParsedResponse : JsonObject;
        DocsArray: JsonArray;
        ApiUrl: Text;
        JsonText: Text;
        RetryCount, MaxRetries : Integer;
        WaitSeconds: Integer;
        RetryAfterArray: array[10] of Text;
        RetryAfterValue, SubmissionUid, Uuid : Text;
        SubmissionToken: JsonToken;
        DocumentIdsToken, DocEntryToken, UuidToken : JsonToken;
        DocumentIds: JsonArray;
        DocEntry: JsonObject;
    begin
        if not MyInvoisSetup.Get('SETUP') then
            Error('MyInvois Setup not found.');

        Token := TokenHelper.GetAccessTokenFromSetup(MyInvoisSetup);

        // Prepare one document in array
        DocJson.Add('internalId', InternalId);
        DocJson.Add('typeName', 'invoice');
        DocJson.Add('typeVersionName', '1.0');
        DocJson.Add('document', SignedJsonText);
        DocsArray.Add(DocJson);
        RootJson.Add('documents', DocsArray);

        RootJson.WriteTo(JsonText);
        RequestContent.WriteFrom(JsonText);
        RequestContent.GetHeaders(Headers);
        Headers.Clear();
        Headers.Add('Content-Type', 'application/json');

        HttpClient.DefaultRequestHeaders().Clear();
        HttpClient.DefaultRequestHeaders().Add('Authorization', 'Bearer ' + Token);

        if MyInvoisSetup.Environment = MyInvoisSetup.Environment::Preprod then
            ApiUrl := 'https://preprod-api.myinvois.hasil.gov.my/api/v1.0/documentsubmissions'
        else
            ApiUrl := 'https://api.myinvois.hasil.gov.my/api/v1.0/documentsubmissions';

        RetryCount := 0;
        MaxRetries := 3;
        WaitSeconds := 5;

        repeat
            if not HttpClient.Post(ApiUrl, RequestContent, Response) then
                Error('Failed to submit signed document batch.');

            if Response.HttpStatusCode() = 429 then begin
                Headers := Response.Headers();
                Headers.GetValues('Retry-After', RetryAfterArray);
                RetryAfterValue := RetryAfterArray[1];

                if RetryAfterValue <> '' then
                    Evaluate(WaitSeconds, RetryAfterValue)
                else
                    WaitSeconds := WaitSeconds * 2;

                RetryCount += 1;
                Sleep(WaitSeconds * 1000);
            end else
                break;
        until RetryCount > MaxRetries;

        if Response.HttpStatusCode() = 429 then
            Error('Rate limit exceeded. Submission failed after multiple retries.');

        Response.Content().ReadAs(ResponseText);
        Message('Document submission response:\n%1', ResponseText);

        // Parse and store submissionUid & uuid
        ParsedResponse.ReadFrom(ResponseText);
        if ParsedResponse.Contains('submissionUid') then begin
            ParsedResponse.Get('submissionUid', SubmissionToken);
            SubmissionUid := SubmissionToken.AsValue().AsText();
        end;

        if ParsedResponse.Contains('documentIds') then begin
            ParsedResponse.Get('documentIds', DocumentIdsToken);
            DocumentIds := DocumentIdsToken.AsArray();
            if DocumentIds.Count() > 0 then begin
                DocumentIds.Get(0, DocEntryToken);
                DocEntry := DocEntryToken.AsObject();
                if DocEntry.Contains('uuid') then begin
                    DocEntry.Get('uuid', UuidToken);
                    Uuid := UuidToken.AsValue().AsText();
                end;
            end;
        end;

        if SalesInvHeader.Get(InternalId) then begin
            SalesInvHeader."MyInvois UUID" := Uuid;
            SalesInvHeader."MyInvois Submission UID" := SubmissionUid;
            SalesInvHeader.Modify();
        end;

        exit(StrSubstNo('Submitted successfully.\nUUID: %1\nSubmission UID: %2', Uuid, SubmissionUid));
    end;
}
