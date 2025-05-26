page 50300 MyInvoisSetupCard
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
            group("API Configuration")
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
                ApplicationArea = All;
                Image = Action;

                trigger OnAction()
                var
                    Token: Text;
                    MyInvoisHelper: Codeunit MyInvoisHelper;
                begin
                    Token := MyInvoisHelper.GetAccessTokenFromSetup(Rec);
                    Message('Access token retrieved: %1', CopyStr(Token, 1, 50) + '...');
                end;
            }
        }
    }

    trigger OnOpenPage()
    var
        Setup: Record MyInvoisSetup;
    begin
        if not Setup.Get('SETUP') then begin
            Setup.Init();
            Setup."Primary Key" := 'SETUP';
            Setup.Insert();
        end;
    end;
}
