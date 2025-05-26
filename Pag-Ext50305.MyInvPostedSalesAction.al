pageextension 50305 MyInvPostedSalesAction extends "Posted Sales Invoice"
{
    actions
    {
        addlast(Processing)
        {
            action(SubmitToMyInvois)
            {
                Caption = 'Submit to MyInvois';
                ApplicationArea = All;
                Image = SendTo;

                trigger OnAction()
                var
                    Submitter: Codeunit "MyInvois Submitter";
                    Msg: Text;
                begin
                    Msg := Submitter.SubmitToMyInvois(Rec);
                    Message(Msg);
                end;
            }
        }
    }
}
