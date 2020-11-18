// Last edited: 17.11.2020 01:50
// Version: 1.0.1

uses SysUtils, Classes;

const
  // Начало периода рестарта сервера
  RestartTime: TDateTime = StrToDateTime('18:58:00');
  // Продолжительность рестарта сервера "ЧЧ:ММ:СС"
  RestartDelay: TDateTime = StrToDateTime('00:05:00');
  // Путь к файлу запуска L2 клиента
  gamePath = 'C:\Games\L2_Interlude_L2KOT.RU\system\l2.exe';
  // Файл с описанием персонажей трейна
  trainMembersFile = 'D:\Adrenalin-Data\Rori_Train.txt';
  // Задержка после закрытия окна L2
  afterCloseGameDelay: cardinal = 3000;
  // Задержка перед повторной проверкой окончания периода рестарта сервера
  serverRestartingCheckDelay: cardinal = 10000;
  // Задержка перед повторной проверкой на дисконект
  disconnectCheckPeriod: cardinal = 3000;
  // Время ожидания прогрузки окна клиента сразу после его старта
  loadingAuthScreenDelay: cardinal = 20000;
  // Задержка после нажатия на "Принять" лицензионное соглашение, "Выбор сервера", "Выбор персонажа"
  ingameScreensDelay: cardinal = 5000;
  // Задержка после входа игру персонажем
  charLoggingInDelay: cardinal = 20000;
  // Периодичность очистки списка неопознанных ботов
  unknownBotsClearDelay: cardinal = 600000;

var
  RestartByTime: boolean;
  log: String;
  // Id=Ticks
  unknownBotsIds: TStringList;
  // Char
  localTrainCharNames: TStringList;

function ShellExecuteW(hwnd: integer; lpOperation, lpFile, lpParameters,
  lpDirectory: PChar; nShowCmd: integer): integer; stdcall;
  external 'Shell32.dll';
function keybd_event(bVk, bScan: byte; dwFlags, dwExtraInfo: integer): integer;
  stdcall; external 'user32.dll';
function ShowWindow(hwnd: cardinal; action: integer): boolean; stdcall;
  external 'user32.dll';

// Чтение названия чаров и их логопасов из файла, запись их в обще-аккаунтовое хранилище ShMem
procedure initTrain;
begin
  unknownBotsIds := TStringList.Create;
  parseTrainFile(trainMembersFile);
  // Если на момент запуска скрипта в боте уже кто-то залогинен, обновляем память
  initBotNumShMem(localTrainCharNames);
  // Залогиниваем всех персонажей трейна по очереди
  if (checkTrainMembersOnline(localTrainCharNames)) then
    print('------- ИНИЦИАЛИЗАЦИЯ ТРЕЙНА ЗАВЕРШЕНА -------');
end;

// Парсим файл со списком персонажей бот-трейна и заполняем память, возвращаем список персонажей трейна
procedure parseTrainFile(trainMembersFile: string);
var
  trainList: TStringList;
  account: String;
  i: integer;
begin
  trainList := TStringList.Create;
  localTrainCharNames := TStringList.Create;
  trainList.LoadFromFile(trainMembersFile);
  for i := 0 to trainList.Count - 1 do
  begin
    writeAccountToShMem(getDelimitedItems(trainList[i], ';'));
    localTrainCharNames.Add(getDelimitedItems(trainList[i], ';')[0]);
  end;
  trainList.Free;
end;

// Функция проверки что все персонажи трейна онлайн
function checkTrainMembersOnline(trainChars: TStringList): boolean;
var
  charName: String;
  i: integer;
begin
  for i := 0 to trainChars.Count - 1 do
  begin
    if (not(isTrainMemberOnline(trainChars[i]))) then
    begin
      log := '==== ' + trainChars[i] + ' !!! OFFLINE !!! ====';
      print(log);
      log := 'Начинаем загрузку персонажа ' +
        trainChars[i];
      print(log);
      bootTrainMember(trainChars[i]);
    end
    else
    begin
      log := '==== ' + trainChars[i] + ' Online ====';
      print(log);
    end;
  end;
  Result := true;
end;

// Функция проверки что персонаж трейна в онлайне
function isTrainMemberOnline(charName: string): boolean;
var
  botNum: integer;
begin
  // Если это первый запуск скрипта и персонаж еще не логинился
  if (getBotNumFromShMem(charName) = -1) then
  begin
    Result := logInToGame(charName);
    exit;
  end;
  if (TBot(BotList[getBotNumFromShMem(charName)]).UserName = charName) then
    Result := (TBot(BotList[getBotNumFromShMem(charName)])
      .Control.Status = lsOnline);
end;

// Функция загрузки персонажа трейна в игру
procedure bootTrainMember(charName: string);
begin
  // Пытаемся залогиниться до победного
  while not(logInToGame(charName)) do
    closeGame(TBot(BotList[getBotNumFromShMem(charName)]));
end;

function logInToGame(charName: string): boolean;
var
  currentBot: TBot;
  logPrefix: string;
begin
  logPrefix := '[' + charName + '] ';
  // Запускаем L2 клиент
  log := logPrefix + 'Попытка запустить L2-клиент...';
  print(log);
  ShellExecuteW(0, 'open', PChar(gamePath), nil, nil, 0);
  Delay(loadingAuthScreenDelay);

  // Вводим логопас
  currentBot := checkBotNumber(charName);
  if (currentBot.Control.LoginStatus = 0) then
  // if (currentBot.Control.GameWindow <> 0) then
  begin
    log := logPrefix + 'Попытка залогиниться...';
    print(log);
    currentBot.Control.AuthLogin(getAccountFromShMem(charName)[1],
      getAccountFromShMem(charName)[2]);
    Delay(ingameScreensDelay);
  end
  else
  begin
    log := logPrefix +
      'Ошибка обнаружения окна L2 на этапе ввода логопаса.';
    print(log);
    Result := false;
    exit;
  end;

  // Принимаем лицензионное соглашение
  if (currentBot.Control.LoginStatus = 1) then
  begin
    log := logPrefix +
      'Попытка принять лицензионное соглашение...';
    print(log);
    currentBot.Control.UseKey('Enter');
    Delay(ingameScreensDelay);
  end
  else
  begin
    log := logPrefix +
      'Ошибка обнаружения экрана принятия лицензионного соглашения.';
    print(log);
    Result := false;
    exit;
  end;

  // Выбираем сервер
  if (currentBot.Control.LoginStatus = 1) then
  begin
    log := logPrefix + 'Попытка выбора сервера...';
    print(log);
    currentBot.Control.UseKey('Enter');
    Delay(ingameScreensDelay);
  end
  else
  begin
    log := logPrefix +
      'Ошибка обнаружения экрана выбора сервера.';
    print(log);
    Result := false;
    exit;
  end;

  // Заходим в игру персонажем
  if (currentBot.Control.LoginStatus = 2) then
  begin
    log := logPrefix +
      'Попытка входа персонажа в игру...';
    print(log);
    currentBot.Control.GameStart;
    Delay(charLoggingInDelay);
  end
  else
  begin
    log := logPrefix +
      'Ошибка обнаружения экрана выбора персонажа.';
    print(log);
    Result := false;
    exit;
  end;

  // Проверяем что успешно зашли
  if (currentBot.Control.Status = lsOnline) then
  begin
    log := logPrefix + 'Активация бота...';
    print(log);
    // Включаем интерфейс
    currentBot.Control.FaceControl(0, true);
    Result := true;
  end
  else
  begin
    log := logPrefix +
      'Ошибка проверки статуса персонажа.';
    print(log);
    Result := false;
    exit;
  end;
  log := logPrefix + 'Бот активирован!';
  print(log);
end;

function checkBotNumber(charName: string): TBot;
var
  botNum: integer;
begin
  botNum := getBotNumFromShMem(charName);
  if (botNum = -1) then
    Result := mapBotNumber(charName)
  else
  begin
    log := '[' + charName + '] ' + ' Использует бота №' +
      IntToStr(botNum);
    print(log);
    Result := TBot(BotList[botNum]);
  end;
end;

// Функция создания привязки Char -> TBot
function mapBotNumber(charName: string): TBot;
var
  botNum: integer;
begin
  botNum := getFirstUnknownBotNum();
  if (botNum = -1) then
    botNum := BotList.Count - 1;
  writeBotNumToShMem(charName, botNum);
  Result := TBot(BotList[botNum]);
end;

// Возвращаем номер первого попавшегося безымянного бота. Возвращаем -1 если не найдены
function getFirstUnknownBotNum(): integer;
var
  i: integer;
begin
  for i := 0 to BotList.Count - 1 do
  begin
    if (TBot(BotList[i]).UserName = '') then
    begin
      Result := i;
      exit;
    end;
  end;
  Result := -1;
end;

// ######################################
// ########### Работа с ShMem ###########

procedure initBotNumShMem(trainCharNames: TStringList);
var
  i, k: integer;
begin
  for i := 0 to trainCharNames.Count - 1 do
  begin
    for k := 0 to BotList.Count - 1 do
    begin
      if (TBot(BotList[k]).UserName = trainCharNames[i]) then
      begin
        writeBotNumToShMem(trainCharNames[i], k);
        break;
      end;
    end;
  end;
end;

// Получаем номер бота персонажа из памяти. При ошибке возвращает -1
function getBotNumFromShMem(charName: String): integer;
var
  charIdx: integer;
begin
  if (ShMem[1] = 0) then
  begin
    // ShMem[1] is not initialized
    Result := -1;
    exit;
  end;
  charIdx := TStringList(ShMem[1]).IndexOfName(charName);
  if (charIdx = -1) then
  begin
    // Character not found in ShMem[1]
    Result := -1;
    exit;
  end;
  Result := StrToInt(TStringList(ShMem[1]).Values[charName]);
end;

// Записываем в память привязку Char=BotNum в память
procedure writeBotNumToShMem(charName: String; botNum: integer);
var
  charIdx: integer;
begin
  if (ShMem[1] = 0) then
  begin
    ShMem[1] := integer(TStringList.Create);
  end;
  charIdx := TStringList(ShMem[1]).IndexOfName(charName);
  if (charIdx = -1) then
  begin
    TStringList(ShMem[1]).Add(charName + '=' + IntToStr(botNum));
    log := 'Сохранена привязка персонажа ' + charName
      + ' к боту №' + IntToStr(botNum) + ' [Память ботов: ' +
      IntToStr(TStringList(ShMem[1]).Count) + ']';
  end
  else
  begin
    TStringList(ShMem[1])[charIdx] := charName + '=' + IntToStr(botNum);
    log := 'Обновлена привязка персонажа ' + charName
      + ' к боту №' + IntToStr(botNum) + ' [Память ботов: ' +
      IntToStr(TStringList(ShMem[1]).Count) + ']';
  end;
  print(log);
end;

// Получаем список Char,Login,Password из памяти
function getAccountFromShMem(charName: string): TStringList;
var
  charIdx: integer;
  results: TStringList;
begin
  results := TStringList.Create;
  if (ShMem[0] = 0) then
  begin
    Result := results;
    log := 'ERROR: ShMem[0] is not initialized.';
    print(log);
    exit;
  end;
  charIdx := TStringList(ShMem[0]).IndexOfName(charName);
  if (charIdx = -1) then
  begin
    Result := results;
    log := 'ERROR: Account not found in ShMem[0].';
    print(log);
    exit;
  end;
  results.Add(charName);
  results.AddStrings(getDelimitedItems(TStringList(ShMem[0])
    .Values[charName], ';'));
  Result := results;
end;

// Записываем в память Char=Login;Password
procedure writeAccountToShMem(accountEntry: TStringList);
var
  charIdx: integer;
begin
  if (ShMem[0] = 0) then
  begin
    ShMem[0] := integer(TStringList.Create);
  end;
  charIdx := TStringList(ShMem[0]).IndexOfName(accountEntry[0]);
  if (charIdx = -1) then
  begin
    TStringList(ShMem[0]).Add(accountEntry[0] + '=' + accountEntry[1] + ';' +
      accountEntry[2]);
    log := 'Сохранён аккаунт персонажа ' + accountEntry
      [0] + ' [Память аккаунтов: ' +
      IntToStr(TStringList(ShMem[0]).Count) + ']';
  end
  else
  begin
    TStringList(ShMem[0])[charIdx] := accountEntry[0] + '=' + accountEntry[1] +
      ';' + accountEntry[2];
    log := 'Обновлен аккаунт персонажа ' + accountEntry
      [0] + ' [Память аккаунтов: ' +
      IntToStr(TStringList(ShMem[0]).Count) + ']';
  end;
  print(log);
end;

// Пример с delim = ';'. На входе 'abc;abc;abc', на выходе список из трёх 'abc'.
function getDelimitedItems(rawString: string; delim: Char): TStringList;
var
  results: TStringList;
begin
  results := TStringList.Create;
  results.Delimiter := delim;
  results.DelimitedText := rawString;
  Result := results;
end;
// ######################################

procedure disconnectMonitor;
var
  i, k, botNum: integer;
begin
  initTrain();
  while Delay(disconnectCheckPeriod) do
  begin
    // Если начал действовать период рестарта сервера
    if (Time > RestartTime) and (Time < RestartTime + RestartDelay) then
      RestartByTime := true
    else
      RestartByTime := false;
    // Проверяем для каждого персонажа трейна
    for i := 0 to localTrainCharNames.Count - 1 do
    begin
      botNum := getBotNumFromShMem(localTrainCharNames[i]);
      // Если имя бота не пустое
      if (TBot(BotList[botNum]).UserName <> '') then
        handleDisconnect(localTrainCharNames[i])
      else
        // Обновляем список игнорируемых безымянных ботов
        refreshUnknownBots(botNum);
    end;
  end;
end;

procedure handleDisconnect(charName: String);
var
  currentBot: TBot;
begin
  currentBot := TBot(BotList[getBotNumFromShMem(charName)]);
  // Ожидаем окончания периода рестарта
  if (RestartByTime) then
  begin
    closeTrainGameWindows();
    if (Time < RestartTime + RestartDelay) then
    begin
      log := '[' + charName + '] ' +
        'Сервер в процессе рестарта...';
      print(log);
      Delay(serverRestartingCheckDelay);
      exit;
    end
    else
      RestartByTime := false;
  end
  else
  begin
    // Если персонаж не в игре, закрываем L2 клиент и пытаемся зайти обратно
    if (currentBot.Control.Status <> lsOnline) and (Not(RestartByTime)) then
    begin
      log := charName + ' ### DISCONNECTED ###';
      print(log);
      // Закрываем L2 клиент, если открыт
      closeGame(currentBot);
      // Пытаемся зайти в игру до победного
      while not(logInToGame(charName)) do
        closeGame(currentBot);
    end;
  end;
end;

procedure closeTrainGameWindows;
var
  i: integer;
begin
  for i := 0 to localTrainCharNames.Count - 1 do
  begin
    closeGame(TBot(BotList[getBotNumFromShMem(localTrainCharNames[i])]));
  end;
end;

procedure closeGame(bot: TBot);
begin
  if (bot.Control.GameWindow <> 0) then
  begin
    bot.Control.FaceControl(0, false);
    bot.Control.GameClose;
    Delay(afterCloseGameDelay);
  end;
end;

procedure refreshUnknownBots(botNum: integer);
var
  i: integer;
  key: String;
begin
  if (unknownBotsIds.Count = 0) or (unknownBotsIds.IndexOfName(IntToStr(botNum))
    = -1) then
  begin
    markUnknownBotIgnored(botNum);
    exit;
  end;
  for i := 0 to unknownBotsIds.Count - 1 do
  begin
    key := unknownBotsIds.Names[i];
    if (StrToInt(unknownBotsIds.Values[key]) + unknownBotsClearDelay <
      GetTickCount()) then
    begin
      unknownBotsIds.Delete(StrToInt(unknownBotsIds[i]));
      log := 'Перестаём игнорировать неопознанного бота №'
        + unknownBotsIds.Values[key];
      print(log);
      exit;
    end;
  end;
end;

procedure markUnknownBotIgnored(botNum: integer);
begin
  unknownBotsIds.Add(IntToStr(botNum) + '=' + IntToStr(GetTickCount()));
  log := 'Неопознанный бот №' + IntToStr(botNum) +
    ' добавлен в список игнорируемых на ' +
    FloatToStr(unknownBotsClearDelay / 1000) + ' секунд.';
  print(log);
end;

begin
  Script.NewThread(@disconnectMonitor);

end.
