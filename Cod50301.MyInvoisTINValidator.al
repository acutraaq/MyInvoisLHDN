codeunit 50301 "MyInvois TIN Validator"
{
    procedure ValidateTIN(var CustomerRec: Record Customer): Text
    var
        MyInvoisSetup: Record "MyInvoisSetup";
        TokenHelper: Codeunit "MyInvoisHelper";
        HttpClient: HttpClient;
        Response: HttpResponseMessage;
        JsonResponse: JsonObject;
        ResponseText: Text;
        Token: Text;
        URL: Text;
        TaxpayerName, TaxpayerStatus : Text;
        TokenValue: JsonToken;
    begin
        if CustomerRec."VAT Registration No." = '' then
            Error('Customer does not have a TIN (VAT Registration No.).');

        if not MyInvoisSetup.Get('SETUP') then
            Error('MyInvois Setup not found.');

        Token := TokenHelper.GetAccessTokenFromSetup(MyInvoisSetup);

        if MyInvoisSetup.Environment = MyInvoisSetup.Environment::Preprod then
            URL := 'https://preprod-api.myinvois.hasil.gov.my/api/v1.0/taxpayer/' + CustomerRec."VAT Registration No."
        else
            URL := 'https://api.myinvois.hasil.gov.my/api/v1.0/taxpayer/' + CustomerRec."VAT Registration No.";

        HttpClient.DefaultRequestHeaders().Clear();
        HttpClient.DefaultRequestHeaders().Add('Authorization', 'Bearer ' + Token);

        HttpClient.Get(URL, Response);
        Response.Content().ReadAs(ResponseText);

        if not Response.IsSuccessStatusCode then
            Error('TIN validation failed (status %1): %2',
                Response.HttpStatusCode(), ResponseText);

        JsonResponse.ReadFrom(ResponseText);

        JsonResponse.Get('name', TokenValue);
        TaxpayerName := TokenValue.AsValue().AsText();

        JsonResponse.Get('status', TokenValue);
        TaxpayerStatus := TokenValue.AsValue().AsText();

        // Update customer record
        CustomerRec."Last Validated TIN Name" := TaxpayerName;
        CustomerRec."Last TIN Validation" := CurrentDateTime();
        CustomerRec.Modify();

        exit(StrSubstNo(
            'TIN: %1\nName: %2\nStatus: %3',
            CustomerRec."VAT Registration No.", TaxpayerName, TaxpayerStatus
        ));
    end;
}
