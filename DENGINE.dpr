program DENGINE;

uses
  Vcl.Forms,
  MainForm in 'Src\View\MainForm.pas' {frmMain};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
