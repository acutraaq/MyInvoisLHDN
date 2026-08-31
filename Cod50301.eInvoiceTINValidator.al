codeunit 50301 "eInvoice TIN Validator"
{
    procedure ValidateTIN(var CustomerRec: Record Customer): Text
    var
        MyInvoisSetup: Record "eInvoiceSetup";
        TokenHelper: Codeunit "eInvoiceHelper";
        HttpClient: HttpClient;
        Response: HttpResponseMessage;
        Token: Text;
        URL: Text;
        TIN: Text;
        IDType: Text;
        IDValue: Text;
        TinLog: Record "eInvoice TIN Log";
        CachedMsg: Text;
        ValidationMsg: Text;
    begin
        // Get field values
        TIN := CustomerRec."e-Invoice TIN No.";
        IDType := Format(CustomerRec."e-Invoice ID Type");
        IDValue := CustomerRec."e-Invoice ID No.";

        // Validate inputs
        if TIN = '' then
            Error('Customer does not have a TIN No.');
        if IDType = '' then
            Error('Customer does not have an e-Invoice ID Type.');
        if IDValue = '' then
            Error('Customer does not have an e-Invoice ID No.');
        if not MyInvoisSetup.Get('API SETUP') then
            Error('eInvois API Setup not found.');

        // Reuse cached result if validated recently (180 days)
        if TryGetCachedTinStatus(CustomerRec, TIN, IDType, IDValue, CachedMsg, true) then
            exit(CachedMsg);

        if not ValidateTinCombination(CustomerRec, TIN, IDType, IDValue, true, true, ValidationMsg) then
            Error(ValidationMsg);

        exit(ValidationMsg);
    end;

    procedure AutoPopulateTinFromId(var CustomerRec: Record Customer; ShowMessages: Boolean): Boolean
    var
        IDType: Text;
        IDValue: Text;
        FoundTIN: Text;
        MessageText: Text;
    begin
        // Only supported for NRIC and BRN lookup flow
        if not (CustomerRec."e-Invoice ID Type" in [CustomerRec."e-Invoice ID Type"::NRIC, CustomerRec."e-Invoice ID Type"::BRN]) then
            exit(false);

        IDType := Format(CustomerRec."e-Invoice ID Type");
        IDValue := CustomerRec."e-Invoice ID No.";

        if IDValue = '' then
            exit(false);

        // Reuse a recent valid mapping from local log to reduce API calls
        if TryGetCachedTinById(CustomerRec, IDType, IDValue, FoundTIN) then begin
            CustomerRec.Validate("e-Invoice TIN No.", CopyStr(FoundTIN, 1, MaxStrLen(CustomerRec."e-Invoice TIN No.")));
            if ShowMessages then
                Message('TIN populated from cache: %1', FoundTIN);
            exit(true);
        end;

        if not SearchTinById(CustomerRec, IDType, IDValue, FoundTIN, MessageText) then begin
            if ShowMessages and (MessageText <> '') then
                Message(MessageText);
            exit(false);
        end;

        CustomerRec.Validate("e-Invoice TIN No.", CopyStr(FoundTIN, 1, MaxStrLen(CustomerRec."e-Invoice TIN No.")));

        if not ValidateTinCombination(CustomerRec, FoundTIN, IDType, IDValue, false, false, MessageText) then begin
            if ShowMessages and (MessageText <> '') then
                Message(MessageText);
            exit(false);
        end;

        if ShowMessages then
            Message('TIN auto-populated and validated.\\TIN: %1', FoundTIN);

        exit(true);
    end;

    local procedure SearchTinById(var CustomerRec: Record Customer; IDType: Text; IDValue: Text; var FoundTIN: Text; var MessageText: Text): Boolean
    var
        MyInvoisSetup: Record "eInvoiceSetup";
        TokenHelper: Codeunit "eInvoiceHelper";
        HttpClient: HttpClient;
        Response: HttpResponseMessage;
        URL: Text;
        ResponseText: Text;
        Token: Text;
        BaseUrl: Text;
        FileType: Text;
    begin
        if not MyInvoisSetup.Get('API SETUP') then begin
            MessageText := 'eInvois API Setup not found.';
            exit(false);
        end;

        Token := TokenHelper.GetAccessTokenFromSetup(MyInvoisSetup);

        if MyInvoisSetup.Environment = MyInvoisSetup.Environment::Preprod then
            BaseUrl := 'https://preprod-api.myinvois.hasil.gov.my'
        else
            BaseUrl := 'https://api.myinvois.hasil.gov.my';

        URL := StrSubstNo('%1/api/v1.0/taxpayer/search/tin?idType=%2&idValue=%3', BaseUrl, IDType, IDValue);

        FileType := GetFileTypeForIdType(CustomerRec."e-Invoice ID Type");
        if FileType <> '' then
            URL += '&fileType=' + FileType;

        HttpClient.DefaultRequestHeaders().Clear();
        HttpClient.DefaultRequestHeaders().Add('Authorization', 'Bearer ' + Token);
        HttpClient.DefaultRequestHeaders().Add('Accept', 'application/json');
        HttpClient.DefaultRequestHeaders().Add('User-Agent', 'BC-eInvoice/1.0');

        if not HttpClient.Get(URL, Response) then begin
            MessageText := 'Failed to call Search Taxpayer TIN API. Please check connectivity.';
            exit(false);
        end;

        Response.Content().ReadAs(ResponseText);

        case Response.HttpStatusCode() of
            200:
                begin
                    if TryExtractTinFromSearchResponse(ResponseText, FoundTIN) then
                        exit(true);

                    MessageText := 'Search Taxpayer TIN API returned success but no TIN was found in the response.';
                    exit(false);
                end;
            400:
                begin
                    MessageText := 'Search Taxpayer TIN failed (400). Input may be invalid or criteria may be inconclusive (multiple matches).';
                    CustomerRec."Validation Status" := CustomerRec."Validation Status"::"Invalid Input";
                    CustomerRec."Last TIN Validation" := CurrentDateTime();
                    exit(false);
                end;
            404:
                begin
                    MessageText := 'No matching TIN found for the provided ID Type and ID No.';
                    CustomerRec."Validation Status" := CustomerRec."Validation Status"::"Not Found";
                    CustomerRec."Last TIN Validation" := CurrentDateTime();
                    exit(false);
                end;
            429:
                begin
                    MessageText := 'Search Taxpayer TIN is rate limited (429). Please try again later.';
                    CustomerRec."Validation Status" := CustomerRec."Validation Status"::"API Error";
                    CustomerRec."Last TIN Validation" := CurrentDateTime();
                    exit(false);
                end;
            else begin
                MessageText := StrSubstNo('Search Taxpayer TIN failed (status %1).', Response.HttpStatusCode());
                CustomerRec."Validation Status" := CustomerRec."Validation Status"::"API Error";
                CustomerRec."Last TIN Validation" := CurrentDateTime();
                exit(false);
            end;
        end;
    end;

    local procedure ValidateTinCombination(var CustomerRec: Record Customer; TIN: Text; IDType: Text; IDValue: Text; ThrowOnError: Boolean; PersistChanges: Boolean; var MessageText: Text): Boolean
    var
        MyInvoisSetup: Record "eInvoiceSetup";
        TokenHelper: Codeunit "eInvoiceHelper";
        HttpClient: HttpClient;
        Response: HttpResponseMessage;
        Token: Text;
        URL: Text;
    begin
        if not MyInvoisSetup.Get('API SETUP') then begin
            MessageText := 'eInvois API Setup not found.';
            if ThrowOnError then
                Error(MessageText);
            exit(false);
        end;

        // Get token
        Token := TokenHelper.GetAccessTokenFromSetup(MyInvoisSetup);

        // Build URL
        if MyInvoisSetup.Environment = MyInvoisSetup.Environment::Preprod then
            URL := StrSubstNo(
                'https://preprod-api.myinvois.hasil.gov.my/api/v1.0/taxpayer/validate/%1?idType=%2&idValue=%3',
                TIN, IDType, IDValue)
        else
            URL := StrSubstNo(
                'https://api.myinvois.hasil.gov.my/api/v1.0/taxpayer/validate/%1?idType=%2&idValue=%3',
                TIN, IDType, IDValue);

        // Make HTTP call
        HttpClient.DefaultRequestHeaders().Clear();
        HttpClient.DefaultRequestHeaders().Add('Authorization', 'Bearer ' + Token);
        HttpClient.DefaultRequestHeaders().Add('Accept', 'application/json');
        HttpClient.DefaultRequestHeaders().Add('User-Agent', 'BC-eInvoice/1.0');

        if not HttpClient.Get(URL, Response) then begin
            MessageText := 'Failed to call Validate Taxpayer TIN API. Please check connectivity.';
            CustomerRec."Validation Status" := CustomerRec."Validation Status"::"API Error";
            CustomerRec."Last TIN Validation" := CurrentDateTime();
            if PersistChanges then
                CustomerRec.Modify();
            if ThrowOnError then
                Error(MessageText);
            exit(false);
        end;

        // Handle response purely based on status code (no body parsing)
        case Response.HttpStatusCode() of
            200:
                begin
                    CustomerRec."Validation Status" := CustomerRec."Validation Status"::"Valid";
                    CustomerRec."Last TIN Validation" := CurrentDateTime();
                    if PersistChanges then
                        CustomerRec.Modify();
                    InsertTinLog(CustomerRec, TIN, 'Valid', IDType, IDValue);
                    MessageText := StrSubstNo('TIN: %1\\Status: Valid', TIN);
                    exit(true);
                end;
            400:
                begin
                    CustomerRec."Validation Status" := CustomerRec."Validation Status"::"Invalid Input";
                    CustomerRec."Last TIN Validation" := CurrentDateTime();
                    if PersistChanges then
                        CustomerRec.Modify();
                    InsertTinLog(CustomerRec, TIN, 'Invalid Input', IDType, IDValue);
                    MessageText := 'TIN validation failed: Bad input format (400).\\Please check the TIN, ID Type, or ID No.';
                    if ThrowOnError then
                        Error(MessageText);
                    exit(false);
                end;
            404:
                begin
                    CustomerRec."Validation Status" := CustomerRec."Validation Status"::"Not Found";
                    CustomerRec."Last TIN Validation" := CurrentDateTime();
                    if PersistChanges then
                        CustomerRec.Modify();
                    InsertTinLog(CustomerRec, TIN, 'Not Found', IDType, IDValue);
                    MessageText := StrSubstNo('TIN: %1\\No taxpayer found for this TIN and ID combination.', TIN);
                    exit(false);
                end;
            else begin
                CustomerRec."Validation Status" := CustomerRec."Validation Status"::"API Error";
                CustomerRec."Last TIN Validation" := CurrentDateTime();
                if PersistChanges then
                    CustomerRec.Modify();
                InsertTinLog(CustomerRec, TIN, 'API Error', IDType, IDValue);
                MessageText := StrSubstNo('TIN validation failed (status %1).', Response.HttpStatusCode());
                if ThrowOnError then
                    Error(MessageText);
                exit(false);
            end;
        end;
    end;

    local procedure TryExtractTinFromSearchResponse(ResponseText: Text; var FoundTIN: Text): Boolean
    var
        ResponseObject: JsonObject;
        TinToken: JsonToken;
    begin
        if not ResponseObject.ReadFrom(ResponseText) then
            exit(false);

        if not ResponseObject.Get('tin', TinToken) then
            exit(false);

        FoundTIN := TinToken.AsValue().AsText();
        exit(FoundTIN <> '');
    end;

    local procedure GetFileTypeForIdType(IdTypeOption: Option NRIC,BRN,PASSPORT,ARMY): Text
    begin
        case IdTypeOption of
            IdTypeOption::NRIC:
                exit('1');
            IdTypeOption::BRN:
                exit('2');
        end;

        exit('');
    end;

    local procedure TryGetCachedTinById(var CustomerRec: Record Customer; IdType: Text; IdValue: Text; var Tin: Text): Boolean
    var
        Log: Record "eInvoice TIN Log";
        CutoffDate: Date;
    begin
        CutoffDate := CalcDate('<-180D>', Today);

        Log.Reset();
        Log.SetRange("Customer No.", CustomerRec."No.");
        Log.SetRange("ID Type", IdType);
        Log.SetRange("ID Value", IdValue);
        Log.SetRange("TIN Status", 'Valid');

        if Log.FindLast() then begin
            if (DT2Date(Log."Response Time") >= CutoffDate) and (Log."TIN" <> '') then begin
                Tin := Log."TIN";
                exit(true);
            end;
        end;

        exit(false);
    end;

    local procedure TryGetCachedTinStatus(var CustomerRec: Record Customer; Tin: Text; IdType: Text; IdValue: Text; var MessageText: Text; PersistChanges: Boolean): Boolean
    var
        Log: Record "eInvoice TIN Log";
        CutoffDate: Date;
        StatusText: Text;
    begin
        CutoffDate := CalcDate('<-180D>', Today);
        Log.Reset();
        Log.SetRange("Customer No.", CustomerRec."No.");
        Log.SetRange("TIN", CopyStr(Tin, 1, 20));
        Log.SetRange("ID Type", IdType);
        Log.SetRange("ID Value", IdValue);

        if Log.FindLast() then begin
            if DT2Date(Log."Response Time") >= CutoffDate then begin
                StatusText := Log."TIN Status";
                case StatusText of
                    'Valid':
                        begin
                            CustomerRec."Validation Status" := CustomerRec."Validation Status"::"Valid";
                            CustomerRec."Last TIN Validation" := CurrentDateTime();
                            if PersistChanges then
                                CustomerRec.Modify();
                            MessageText := StrSubstNo('TIN: %1\\Status: Valid (cached)', Tin);
                            exit(true);
                        end;
                    'Not Found':
                        begin
                            CustomerRec."Validation Status" := CustomerRec."Validation Status"::"Not Found";
                            CustomerRec."Last TIN Validation" := CurrentDateTime();
                            if PersistChanges then
                                CustomerRec.Modify();
                            MessageText := StrSubstNo('TIN: %1\\No taxpayer found (cached).', Tin);
                            exit(true);
                        end;
                end;
            end;
        end;

        exit(false);
    end;

    local procedure InsertTinLog(var CustomerRec: Record Customer; Tin: Text; StatusText: Text; IdType: Text; IdValue: Text)
    var
        Log: Record "eInvoice TIN Log";
    begin
        if CustomerRec."No." = '' then
            exit;

        Log.Init();
        Log.Validate("Customer No.", CustomerRec."No.");
        Log.Validate("Customer Name", CustomerRec.Name);
        Log.Validate("TIN", CopyStr(Tin, 1, 20));
        Log.Validate("TIN Status", StatusText);
        Log.Validate("Response Time", CurrentDateTime());
        Log.Validate("ID Type", IdType);
        Log.Validate("ID Value", CopyStr(IdValue, 1, 150));
        Log.Insert(true);
    end;
}