unit MainFormU;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, MVCFramework.AsyncTask, Vcl.StdCtrls;

type
  TMainForm = class(TForm)
    btnAsync1: TButton;
    Edit1: TEdit;
    btnWithEx: TButton;
    procedure btnAsync1Click(Sender: TObject);
    procedure btnWithExClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

procedure TMainForm.btnAsync1Click(Sender: TObject);
begin
  btnAsync1.Enabled := False;
  MVCAsync.Run<String>(
    function: String
    begin
      Sleep(1000);
      Result := DateTimeToStr(Now);
    end,
    procedure(const Value: String)
    begin
      Edit1.Text := Value;
      btnAsync1.Enabled := True;
    end
  );
end;

procedure TMainForm.btnWithExClick(Sender: TObject);
begin
  MVCAsync.Run<String>(
    function: String
    begin
      Sleep(1000);
      raise Exception.Create('BOOOM!');
    end,
    procedure(const Value: String)
    begin
      //never called
    end,
    procedure(const Expt: Exception)
    begin
      ShowMessage(Expt.Message);
    end
  );
end;

end.
