codeunit 50100 MyInvoisHelper
{
    procedure GetAccessTokenFromSetup(var SetupRec: Record MyInvoisSetup): Text
    var
        HttpClient: HttpClient;
        HttpContent: HttpContent;
        ResponseMessage: HttpResponseMessage;
        Headers: HttpHeaders;
        ResponseText: Text;
        JsonResponse: JsonObject;
        TokenValue: JsonToken;
        TokenURL: Text;
        AccessToken: Text;
    begin
        // Set token URL based on environment
        if SetupRec.Environment = SetupRec.Environment::Preprod then
            TokenURL := 'https://preprod-api.myinvois.hasil.gov.my/token'
        else
            TokenURL := 'https://api.myinvois.hasil.gov.my/token';

        // Build content (x-www-form-urlencoded)
        HttpContent.WriteFrom(
            'grant_type=client_credentials' +
            '&client_id=' + SetupRec."Client ID" +
            '&client_secret=' + SetupRec."Client Secret"
        );

        // Set headers correctly using var
        HttpContent.GetHeaders(Headers); // ✅ No "var" keyword here
        Headers.Add('Content-Type', 'application/x-www-form-urlencoded');

        // Send POST request
        if not HttpClient.Post(TokenURL, HttpContent, ResponseMessage) then
            Error('Failed to send request to MyInvois token endpoint.');

        // Read and parse response
        ResponseMessage.Content().ReadAs(ResponseText);
        JsonResponse.ReadFrom(ResponseText);

        // Extract token
        if JsonResponse.Contains('access_token') then begin
            JsonResponse.Get('access_token', TokenValue);
            AccessToken := TokenValue.AsValue().AsText();

            // Save in setup record
            SetupRec."Last Token" := AccessToken;
            SetupRec."Token Timestamp" := CurrentDateTime();
            SetupRec.Modify();

            exit(AccessToken);
        end else
            Error('Access token not found in the API response.');
    end;
}
