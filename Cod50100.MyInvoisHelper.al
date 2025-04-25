codeunit 50100 MyInvoisHelper
{
    procedure GetAccessTokenFromSetup(var SetupRec: Record MyInvoisSetup): Text
    var
        HttpClient: HttpClient;
        HttpContent: HttpContent;
        Headers: HttpHeaders;
        ResponseMessage: HttpResponseMessage;
        ResponseText: Text;
        JsonResponse: JsonObject;
        TokenValue: JsonToken;
        TokenURL: Text;
        AccessToken: Text;
        Body: Text;
        TempBlob: Codeunit "Temp Blob";
        OutS: OutStream;
        InS: InStream;
    begin
        // ✅ Use correct token URL
        if SetupRec.Environment = SetupRec.Environment::Preprod then
            TokenURL := 'https://preprod-api.myinvois.hasil.gov.my/connect/token'
        else
            TokenURL := 'https://api.myinvois.hasil.gov.my/connect/token';

        // ✅ Encode body properly
        Body :=
            'grant_type=client_credentials' +
            '&client_id=' + EncodeUriComponent(SetupRec."Client ID") +
            '&client_secret=' + EncodeUriComponent(SetupRec."Client Secret");

        // ✅ Use TempBlob to avoid WriteFrom() encoding issues
        TempBlob.CreateOutStream(OutS);
        OutS.WriteText(Body); // This writes UTF-8 without BOM
        TempBlob.CreateInStream(InS);
        HttpContent.WriteFrom(InS);

        // ✅ Set content-type header
        HttpContent.GetHeaders(Headers);
        if not Headers.Contains('Content-Type') then
            Headers.Add('Content-Type', 'application/x-www-form-urlencoded');

        // ✅ Send the request
        if not HttpClient.Post(TokenURL, HttpContent, ResponseMessage) then
            Error('Failed to send request to MyInvois token endpoint.');

        // ✅ Read response
        ResponseMessage.Content().ReadAs(ResponseText);
        Message('Response from MyInvois:\n%1', ResponseText);

        JsonResponse.ReadFrom(ResponseText);
        if JsonResponse.Contains('access_token') then begin
            JsonResponse.Get('access_token', TokenValue);
            AccessToken := TokenValue.AsValue().AsText();

            SetupRec."Last Token" := AccessToken;
            SetupRec."Token Timestamp" := CurrentDateTime();
            SetupRec.Modify();

            exit(AccessToken);
        end else
            Error('Access token not found in response.');
    end;

    local procedure EncodeUriComponent(Value: Text): Text
    begin
        Value := Value.Replace(' ', '%20');
        Value := Value.Replace('"', '%22');
        Value := Value.Replace(':', '%3A');
        Value := Value.Replace('/', '%2F');
        Value := Value.Replace('+', '%2B');
        Value := Value.Replace('=', '%3D');
        exit(Value);
    end;
}
