namespace KMAXDev.KMAXDev;

page 50100 MyInvoisSetupCard
{
    PageType = Card;
    SourceTable = MyInvoisSetup;
    Caption = 'MyInvois Setup';
    UsageCategory = Administration;
    ApplicationArea = All;

    layout
    {
        area(content)
        {
            group("API Credentials")
            {
                field("Client ID"; Rec."Client ID") { ApplicationArea = All; }
                field("Client Secret"; Rec."Client Secret") { ApplicationArea = All; }
                field("Environment"; Rec.Environment) { ApplicationArea = All; }
            }

            group("Token Info")
            {
                field("Last Token"; Rec."Last Token") { ApplicationArea = All; Editable = false; }
                field("Token Timestamp"; Rec."Token Timestamp") { ApplicationArea = All; Editable = false; }
            }
        }
    }

    actions
    {
        area(processing)
        {
            action(TestConnection)
            {
                Caption = 'Test Connection';
                Image = Action;
                ApplicationArea = All;

                trigger OnAction()
                var
                    MyInvoisHelper: Codeunit MyInvoisHelper;
                    Token: Text;
                begin
                    Token := MyInvoisHelper.GetAccessTokenFromSetup(Rec);
                    Message('Access token retrieved: %1', CopyStr(Token, 1, 50) + '...');
                end;
            }
        }
    }

    trigger OnOpenPage()
    var
        SetupRec: Record MyInvoisSetup;
    begin
        if not SetupRec.Get('SETUP') then begin
            SetupRec.Init();
            SetupRec."Primary Key" := 'SETUP'; // ✅ Set explicitly to avoid duplicate error
            SetupRec.Insert();
        end;
    end;
}
