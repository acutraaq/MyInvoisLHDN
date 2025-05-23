pageextension 50104 MyInvCustomerCardExt extends "Customer Card"
{
    actions
    {
        addlast(Navigation)
        {
            action(ValidateTIN)
            {
                Caption = 'Validate TIN (MyInvois)';
                Image = Check;
                ApplicationArea = All;

                trigger OnAction()
                var
                    Validator: Codeunit "MyInvois TIN Validator";
                    Msg: Text;
                begin
                    Msg := Validator.ValidateTIN(Rec);
                    Message(Msg);
                end;
            }
        }
    }
}
