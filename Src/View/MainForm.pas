unit MainForm;

interface

uses
  Windows, Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, OpenGL, Math, UITypes, SyncObjs;

const
  WIDTH = 800;
  HEIGHT = 600;
  GRID_SPACING = 1;
  GRID_SIZE = 100;
  CameraSpeed = 0.1;
  MouseSensitivity = 0.0001;

type
  TVector3 = record
  private
    const EPSILON = 1E-6;
  public
    x, y, z: Single;
    constructor Create(ax, ay, az: Single);
    function Normalize: TVector3;
    function Dot(const b: TVector3): Single;
    function RotateYaw(angle: Single): TVector3;
    function RotatePitch(angle: Single): TVector3;
    function Cross(b: TVector3): TVector3;
    class operator Add(const a, b: TVector3): TVector3;
    class operator Subtract(const a, b: TVector3): TVector3;
    class operator Multiply(const a: TVector3; const b: Single): TVector3;
  end;

type
  TfrmMain = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
   private
    private
    hDC: HDC; // Handle para o Device Context
    hRC: HGLRC; // Handle para o Rendering Context (OpenGL)

    LastTime: Cardinal; // Tempo da última atualização
    FrameCount: Integer; // Contador de frames
    FPS: Single; // Frames por segundo

    // Variáveis de câmera
    CameraPos: TVector3;
    CameraDir: TVector3;
    CameraUp: TVector3;

     // Variáveis para controle do mouse
    MouseDown: Boolean;
    LastMouseX, LastMouseY: Integer;
    CameraRotationX, CameraRotationY: Single;

    procedure RenderRayTracedScene;
    procedure InitializeOpenGL;
    procedure DrawFrame;
    function RaySphereIntersection(const origin, dir, spherePos: TVector3; sphereRadius: Single; out t: Single): Boolean;
    procedure UpdateCamera; // Atualiza a câmera

    procedure DrawSphere(radius: Single; slices: Integer; stacks: Integer);

    procedure MouseMoveHandler(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure MouseDownHandler(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure MouseUpHandler(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure KeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
    procedure IdleHandler(Sender: TObject; var Done: Boolean);

  end;

type
  TRenderCameraThread = class(TThread)
  private
    FDelay: Integer;
    ChannelId: BYTE;
    fCritSec: TCriticalSection;

  procedure IdleHandler();

  protected
    procedure Execute; override;
  public
    constructor Create(SleepTime: Integer); overload;
  end;

type
  TWGLSwapIntervalEXT = function(interval: Integer): BOOL; stdcall;

var
  wglSwapIntervalEXT: TWGLSwapIntervalEXT = nil;

var
  frmMain: TfrmMain;
  RenderCameraThread: TRenderCameraThread;

implementation

{$R *.dfm}

{ TVector3 }
constructor TVector3.Create(ax, ay, az: Single);
begin
  x := ax;
  y := ay;
  z := az;
end;

function TVector3.Normalize: TVector3;
var
  len: Single;
begin
  len := Sqrt(x * x + y * y + z * z);
  if len < EPSILON then // Use a pequena constante para evitar problemas com valores pequenos
    Exit(TVector3.Create(0, 0, 0)); // Retornar um vetor nulo se a normalização for inválida
  Result := TVector3.Create(x / len, y / len, z / len);
end;

function TVector3.Dot(const b: TVector3): Single;
begin
  Result := (x * b.x) + (y * b.y) + (z * b.z);
end;

class operator TVector3.Add(const a, b: TVector3): TVector3;
begin
  Result.x := a.x + b.x;
  Result.y := a.y + b.y;
  Result.z := a.z + b.z;
end;

class operator TVector3.Subtract(const a, b: TVector3): TVector3;
begin
  Result.x := a.x - b.x;
  Result.y := a.y - b.y;
  Result.z := a.z - b.z;
end;

class operator TVector3.Multiply(const a: TVector3; const b: Single): TVector3;
begin
  Result.x := a.x * b;
  Result.y := a.y * b;
  Result.z := a.z * b;
end;

function TVector3.RotateYaw(angle: Single): TVector3;
var
  cosAngle, sinAngle: Single;
begin
  cosAngle := Cos(angle);
  sinAngle := Sin(angle);
  Result := TVector3.Create(x * cosAngle - z * sinAngle, y, x * sinAngle + z * cosAngle);
end;

function TVector3.RotatePitch(angle: Single): TVector3;
var
  cosAngle, sinAngle: Single;
begin
  cosAngle := Cos(angle);
  sinAngle := Sin(angle);
  Result := TVector3.Create(x, y * cosAngle - z * sinAngle, y * sinAngle + z * cosAngle);
end;

function TVector3.Cross(b: TVector3): TVector3;
begin
  Result := TVector3.Create(
    y * b.z - z * b.y, // x component
    z * b.x - x * b.z, // y component
    x * b.y - y * b.x  // z component
  );
end;

{ TForm1 }
procedure TfrmMain.InitializeOpenGL;
var
  pfd: PIXELFORMATDESCRIPTOR;
  pixelFormat: Integer;
begin
  // Obter o handle do DC da janela
  hDC := GetDC(Handle);

  // Descrever o formato do pixel
  FillChar(pfd, SizeOf(pfd), 0);
  pfd.nSize := SizeOf(pfd);
  pfd.nVersion := 1;
  pfd.dwFlags := PFD_DRAW_TO_WINDOW or PFD_SUPPORT_OPENGL or PFD_DOUBLEBUFFER;
  pfd.iPixelType := PFD_TYPE_RGBA;
  pfd.cColorBits := 24;
  pfd.cDepthBits := 32;
  pfd.iLayerType := PFD_MAIN_PLANE;

  // Escolher o formato de pixel adequado
  pixelFormat := ChoosePixelFormat(hDC, @pfd);
  SetPixelFormat(hDC, pixelFormat, @pfd);

  // Criar o contexto de renderização OpenGL
  hRC := wglCreateContext(hDC);
  wglMakeCurrent(hDC, hRC);

   @wglSwapIntervalEXT := wglGetProcAddress('wglSwapIntervalEXT');
  if Assigned(wglSwapIntervalEXT) then
    wglSwapIntervalEXT(1);

  // Configurar OpenGL
  glClearColor(0.0, 0.0, 0.0, 1.0); // Cor de fundo preta
  glViewport(0, 0, ClientWidth, ClientHeight); // Configurar o viewport

  // Inicializar a câmera
  CameraPos := TVector3.Create(0, 0, 5);
  CameraDir := TVector3.Create(0, 0, -1);
  CameraUp := TVector3.Create(0, 1, 0);

  glMatrixMode(GL_PROJECTION);
  glLoadIdentity();
  glOrtho(-WIDTH/2, WIDTH/2, -HEIGHT/2, HEIGHT/2, -1, 1); // Configuração ortográfica
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity();
end;

procedure TfrmMain.RenderRayTracedScene;
var
  x, y, z, i: Integer;
  color: TVector3;
  origin, dir, lightPos, spherePos: TVector3;
  sphereRadius, shadowOffset: Single;
  t: Single;
  hitPoint, normal, lightDir, shadowPos: TVector3;
begin
  // Limpar o buffer de cor e profundidade
    // Limpar o buffer de cor e profundidade
  //glClearDepth(1.0);

  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);
  glLoadIdentity;
{$REGION 'Fundo cor e configuracao'}
  glClearColor(0.35, 0.35, 0.35, 1.0); // Cor cinza para o fundo
  glClear(GL_COLOR_BUFFER_BIT);
  glBegin(GL_POINTS);
  glEnd;
{$ENDREGION}
{$REGION 'Camera configuracao e atualizacao'}
  // Configurar a perspectiva da câmera
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  gluPerspective(35.0, ClientWidth / ClientHeight, 1.0, 100.0); // Perspectiva
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;
  UpdateCamera;
{$ENDREGION}
{$REGION 'Grade de fundo configuracao e atualizacao'}
  // Desenhar a grade de fundo 3D
  glColor3f(0.67, 0.67, 0.67); // Cor das linhas da grade
  glBegin(GL_LINES);
  // Linhas no plano XY
  for i := -GRID_SIZE to GRID_SIZE do
  begin
    // Linhas horizontais no plano XY
    glVertex3f(-GRID_SIZE * GRID_SPACING, 0.0, i * GRID_SPACING);
    glVertex3f(GRID_SIZE * GRID_SPACING, 0.0, i * GRID_SPACING);

    // Linhas verticais no plano XY
    glVertex3f(i * GRID_SPACING, 0.0, -GRID_SIZE * GRID_SPACING);
    glVertex3f(i * GRID_SPACING, 0.0, GRID_SIZE * GRID_SPACING);
  end;

  // Linhas no plano XZ
 { for i := -GRID_SIZE to GRID_SIZE do
  begin
    // Linhas horizontais no plano XZ
    glVertex3f(-GRID_SIZE * GRID_SPACING, i * GRID_SPACING, 0.0);
    glVertex3f(GRID_SIZE * GRID_SPACING, i * GRID_SPACING, 0.0);

    // Linhas verticais no plano XZ
    glVertex3f(i * GRID_SPACING, -GRID_SIZE * GRID_SPACING, 0.0);
    glVertex3f(i * GRID_SPACING, GRID_SIZE * GRID_SPACING, 0.0);
  end;  }

  // Linhas no plano YZ
 { for i := -GRID_SIZE to GRID_SIZE do
  begin
    // Linhas verticais no plano YZ
    glVertex3f(0.0, -GRID_SIZE * GRID_SPACING, i * GRID_SPACING);
    glVertex3f(0.0, GRID_SIZE * GRID_SPACING, i * GRID_SPACING);

    // Linhas horizontais no plano YZ
    glVertex3f(0.0, i * GRID_SPACING, -GRID_SIZE * GRID_SPACING);
    glVertex3f(0.0, i * GRID_SPACING, GRID_SIZE * GRID_SPACING);
  end;
         }

  glEnd;
{$ENDREGION}
{$REGION 'Objetos em cena e luzes'}
  spherePos := TVector3.Create(0, 0, -5);
  sphereRadius := 1.0;
  lightPos := TVector3.Create(5, 5, 10); // Ajustar a posição da luz
{$ENDREGION}
{$REGION 'Renderizacao pixel a pixel'}
  //glBegin(GL_POINTS);
 { for y := 0 to HEIGHT - 1 do
  begin
    for x := 0 to WIDTH - 1 do
    begin
      // Ray tracing básico para cada pixel
      origin := TVector3.Create(0, 0, 0);
      dir := TVector3.Create((x - WIDTH / 2) / (WIDTH / 2), (y - HEIGHT / 2) / (HEIGHT / 2), -1).Normalize;

      // Calculo da interseção com a esfera
      if RaySphereIntersection(origin, dir, spherePos, sphereRadius, t) then
      begin
        // Ponto de impacto na esfera
        hitPoint := origin + (dir * t);
        normal := (hitPoint - spherePos).Normalize;

        // Direção da luz e intensidade
        lightDir := (lightPos - hitPoint).Normalize;
        color := TVector3.Create(1, 0, 0) * Max(0.1, normal.Dot(lightDir)); // Cor vermelha para a esfera


        shadowOffset := 0.2; // Ajustar o offset da sombra
        shadowPos := TVector3.Create(hitPoint.x, hitPoint.y - shadowOffset, hitPoint.z);
        // Desenhar a esfera
        glColor3f(color.x, color.y, color.z);
        glVertex3f((x - WIDTH / 2) / (WIDTH / 2), (y - HEIGHT / 2) / (HEIGHT / 2), -5); // Ajustar a posição do pixel

        // Desenhar a sombra (simples projeção no plano de fundo)
        glColor3f(0.2, 0.2, 0.2); // Cor da sombra (preto)
        glVertex2i(Round(shadowPos.x - WIDTH / 2), Round(shadowPos.y - HEIGHT / 2)); // Ajustar a posição da sombra
      end
      else
      begin
        // Fundo cinza já configurado
        glColor3f(0.5, 0.5, 0.5); // Cor cinza para o fundo
        glVertex2i(x - WIDTH div 2, y - HEIGHT div 2); // Ajustar a posição do pixel
      end;
    end;
  end;  }

 // glEnd;
  glColor3f(1.0, 0.0, 0.0); // Cor vermelha
  DrawSphere(2.0, 30, 30);
  //DrawSphere(-2.0, 30, 30);
  SwapBuffers(hDC);

{$ENDREGION}
end;
procedure TfrmMain.DrawSphere(radius: Single; slices: Integer; stacks: Integer);
var
  i, j: Integer;
  theta, phi: Single;
  theta1, phi1: Single;
  x, y, z: Single;
  x1, y1, z1: Single;
  x2, y2, z2: Single;
  x3, y3, z3: Single;
begin
  glBegin(GL_TRIANGLES);
  for i := 0 to stacks - 1 do
  begin
    phi := Pi * (i / stacks); // Latitude atual
    phi1 := Pi * ((i + 1) / stacks); // Latitude da próxima

    for j := 0 to slices - 1 do
    begin
      theta := 2 * Pi * (j / slices); // Longitude atual
      theta1 := 2 * Pi * ((j + 1) / slices); // Longitude da próxima

      // Ponto 1
      x := radius * Sin(phi) * Cos(theta);
      y := radius * Cos(phi);
      z := radius * Sin(phi) * Sin(theta);

      // Ponto 2
      x1 := radius * Sin(phi1) * Cos(theta);
      y1 := radius * Cos(phi1);
      z1 := radius * Sin(phi1) * Sin(theta);

      // Ponto 3
      x2 := radius * Sin(phi1) * Cos(theta1);
      y2 := radius * Cos(phi1);
      z2 := radius * Sin(phi1) * Sin(theta1);

      // Ponto 4
      x3 := radius * Sin(phi) * Cos(theta1);
      y3 := radius * Cos(phi);
      z3 := radius * Sin(phi) * Sin(theta1);

      // Triângulo 1
      glVertex3f(x, y, z);
      glVertex3f(x1, y1, z1);
      glVertex3f(x2, y2, z2);

      // Triângulo 2
      glVertex3f(x, y, z);
      glVertex3f(x2, y2, z2);
      glVertex3f(x3, y3, z3);
    end;
  end;
  glEnd;
end;

procedure TfrmMain.MouseMoveHandler(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  dx, dy: Single;
begin
  if MouseDown then
  begin
    dx := (X - LastMouseX) * MouseSensitivity;
    dy := (Y - LastMouseY) * MouseSensitivity;

    CameraRotationX := CameraRotationX + dx;
    CameraRotationY := CameraRotationY + dy;
    LastMouseX := X;
    LastMouseY := Y;

    //Invalidate; // Solicitar atualização da tela
  end
  else
  begin
    CameraRotationX := 0;
    CameraRotationY := 0;
  end;
end;

procedure TfrmMain.MouseDownHandler(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbRight then
  begin
    MouseDown := True;
    LastMouseX := X;
    LastMouseY := Y;
  end;
end;

procedure TfrmMain.MouseUpHandler(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbRight then
  begin
    MouseDown := False;
  end;
end;

procedure TfrmMain.KeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
const
  MoveSpeed = 0.5;
begin

  case Key of
    VK_UP,vkW : CameraPos := CameraPos + CameraDir * MoveSpeed;
    VK_DOWN,vkS: CameraPos := CameraPos - CameraDir * MoveSpeed;
    VK_LEFT,vkA: CameraPos := CameraPos - (CameraDir.Cross(CameraUp)).Normalize * MoveSpeed;
    VK_RIGHT,vkD: CameraPos := CameraPos + (CameraDir.Cross(CameraUp)).Normalize * MoveSpeed;
  end;
  //Invalidate; // Solicitar atualização da tela
end;

procedure TfrmMain.UpdateCamera;
begin
  // Atualizar a matriz de visualização com a posição da câmera
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity();
   // Aplicar rotação da câmera
  if(MouseDown) then
  begin
    CameraDir := CameraDir.RotateYaw(CameraRotationX).RotatePitch(CameraRotationY);
    CameraUp := CameraUp.RotateYaw(CameraRotationX).RotatePitch(CameraRotationY);
  end;

  gluLookAt(CameraPos.x, CameraPos.y, CameraPos.z,
            CameraPos.x + CameraDir.x, CameraPos.y + CameraDir.y, CameraPos.z + CameraDir.z,
            CameraUp.x, CameraUp.y, CameraUp.z);

end;

function TfrmMain.RaySphereIntersection(const origin, dir, spherePos: TVector3; sphereRadius: Single; out t: Single): Boolean;
var
  oc: TVector3;
  a, b, c, discriminant: Single;
begin
  oc := origin - spherePos;
  a := dir.Dot(dir);
  b := 2.0 * oc.Dot(dir);
  c := oc.Dot(oc) - sphereRadius * sphereRadius;
  discriminant := b * b - 4 * a * c;

  if discriminant < 0 then
  begin
    Result := False;
    Exit;
  end;

  t := (-b - Sqrt(discriminant)) / (2.0 * a);
  if t < 0 then
  begin
    t := (-b + Sqrt(discriminant)) / (2.0 * a);
  end;
  Result := t >= 0;
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  Self.Width := WIDTH;
  Self.Height := HEIGHT;

  InitializeOpenGL;
  RenderCameraThread := TRenderCameraThread.Create(500);
  Application.OnIdle := IdleHandler;
  OnMouseMove := MouseMoveHandler;
  OnMouseDown := MouseDownHandler;
  OnMouseUp := MouseUpHandler;
  OnKeyDown := KeyDownHandler;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  // Liberar o contexto OpenGL e o DC
  wglMakeCurrent(0, 0);
  wglDeleteContext(hRC);
  ReleaseDC(Handle, hDC);
end;

procedure TfrmMain.IdleHandler(Sender: TObject; var Done: Boolean);
var
  CurrentTime: Cardinal;
  DeltaTime: Single;
begin
  DrawFrame;
  Inc(FrameCount);
  Done := False;
end;

procedure TfrmMain.DrawFrame;
begin
  RenderRayTracedScene;

end;

{ TRenderCameraThread }

constructor TRenderCameraThread.Create(SleepTime: Integer);
begin

  Self.FDelay := SleepTime;
  inherited Create(False);
end;

procedure TRenderCameraThread.Execute;
var
  FDone: Boolean;
begin
  frmMain.LastTime := GetTickCount; // Captura o tempo inicial
  frmMain.FrameCount := 0;

  while(Application.Active) do
  begin
    Self.IdleHandler();
    Sleep(Self.FDelay);
  end;
end;

procedure TRenderCameraThread.IdleHandler();
var
  CurrentTime: Cardinal;
  DeltaTime: Single;
begin

  CurrentTime := GetTickCount;
  DeltaTime := (CurrentTime - frmMain.LastTime) / 1000.0;
  if DeltaTime >= 1.0 then
  begin
    frmMain.FPS := frmMain.FrameCount / DeltaTime;
    frmMain.LastTime := CurrentTime;
    frmMain.FrameCount := 0;

    // Atualiza o título do formulário com o FPS
    frmMain.Caption := Format('DENGINE :: FPS: %.2f', [frmMain.FPS]);
  end;
end;

end.
