codeunit 50300 MyInvoisHelper
{
    procedure GetAccessTokenFromSetup(var SetupRec: Record MyInvoisSetup): Text
    var
        Token: Text;
        ExpirySeconds: Integer;
        ExpiryTime: DateTime;
    begin
        // ✅ Reuse existing token if still valid
        if (SetupRec."Last Token" <> '') and (SetupRec."Token Timestamp" <> 0DT) and (SetupRec."Token Expiry (s)" > 0) then begin
            ExpiryTime := SetupRec."Token Timestamp" + (1000 * SetupRec."Token Expiry (s)"); // milliseconds
            if ExpiryTime > CurrentDateTime() then
                exit(SetupRec."Last Token");
        end;

        // ❌ Token missing or expired – generate new
        Token := GetAccessTokenFromFields(
            SetupRec."Client ID",
            SetupRec."Client Secret",
            SetupRec.Environment,
            ExpirySeconds
        );

        SetupRec."Last Token" := Token;
        SetupRec."Token Timestamp" := CurrentDateTime();
        SetupRec."Token Expiry (s)" := ExpirySeconds;
        SetupRec.Modify();

        exit(Token);
    end;

    procedure GetAccessTokenFromFields(ClientID: Text; ClientSecret: Text; Env: Option Preprod,Production; var ExpirySeconds: Integer): Text
    var
        HttpClient: HttpClient;
        ResponseMessage: HttpResponseMessage;
        ResponseText: Text;
        JsonResponse: JsonObject;
        TokenValue, ExpiryValue : JsonToken;
        TokenURL: Text;
        AccessToken: Text;
        BodyText: Text;
        Content: HttpContent;
        Headers: HttpHeaders;
    begin
        ExpirySeconds := 0;

        if (ClientID = '') or (ClientSecret = '') then
            Error('Client ID or Client Secret is blank.');

        if Env = Env::Preprod then
            TokenURL := 'https://preprod-api.myinvois.hasil.gov.my/connect/token'
        else
            TokenURL := 'https://api.myinvois.hasil.gov.my/connect/token';

        BodyText := StrSubstNo(
            'grant_type=client_credentials&client_id=%1&client_secret=%2&scope=InvoicingAPI',
            ClientID,
            ClientSecret
        );

        Content.WriteFrom(BodyText);
        Content.GetHeaders(Headers);
        Headers.Clear();
        Headers.Add('Content-Type', 'application/x-www-form-urlencoded');

        HttpClient.DefaultRequestHeaders().Clear();

        if not HttpClient.Post(TokenURL, Content, ResponseMessage) then
            Error('Failed to send request to MyInvois token endpoint.');

        ResponseMessage.Content().ReadAs(ResponseText);
        JsonResponse.ReadFrom(ResponseText);

        if JsonResponse.Contains('access_token') then begin
            JsonResponse.Get('access_token', TokenValue);
            AccessToken := TokenValue.AsValue().AsText();

            if JsonResponse.Contains('expires_in') then begin
                JsonResponse.Get('expires_in', ExpiryValue);
                ExpirySeconds := ExpiryValue.AsValue().AsInteger();
            end;

            exit(AccessToken);
        end else
            Error('Access token not found in response. Response: %1', ResponseText);
    end;
}