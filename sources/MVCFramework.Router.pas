// ***************************************************************************
//
// Delphi MVC Framework
//
// Copyright (c) 2010-2020 Daniele Teti and the DMVCFramework Team
//
// https://github.com/danieleteti/delphimvcframework
//
// Collaborators on this file: Ezequiel Juliano M�ller (ezequieljuliano@gmail.com)
//
// ***************************************************************************
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// *************************************************************************** }

unit MVCFramework.Router;

{$I dmvcframework.inc}

interface

uses
  System.Rtti,
  System.SysUtils,
  System.Generics.Collections,
  System.RegularExpressions,
  MVCFramework,
  MVCFramework.Commons,
  IdURI;

type
  TMVCActionParamCacheItem = class
  private
    FValue: string;
    FParams: TList<string>;
  public
    constructor Create(aValue: string; aParams: TList<string>); virtual;
    destructor Destroy; override;
    function Value: string;
    function Params: TList<string>; // this should be read-only...
  end;

  TMVCRouter = class(TMVCCustomRouter)
  private
    FRttiContext: TRttiContext;
    FConfig: TMVCConfig;
    FMethodToCall: TRttiMethod;
    FControllerClazz: TMVCControllerClazz;
    FControllerCreateAction: TMVCControllerCreateAction;
    FActionParamsCache: TMVCStringObjectDictionary<TMVCActionParamCacheItem>;
    function GetAttribute<T: TCustomAttribute>(const AAttributes: TArray<TCustomAttribute>): T;
    function GetFirstMediaType(const AContentType: string): string;

    function IsHTTPContentTypeCompatible(
      const ARequestMethodType: TMVCHTTPMethodType;
      var AContentType: string;
      const AAttributes: TArray<TCustomAttribute>): Boolean;

    function IsHTTPAcceptCompatible(
      const ARequestMethodType: TMVCHTTPMethodType;
      var AAccept: string;
      const AAttributes: TArray<TCustomAttribute>): Boolean;

    function IsHTTPMethodCompatible(
      const AMethodType: TMVCHTTPMethodType;
      const AAttributes: TArray<TCustomAttribute>): Boolean;

    function IsCompatiblePath(
      const AMVCPath: string;
      const APath: string;
      var aParams: TMVCRequestParamsTable): Boolean;
    function GetParametersNames(const V: string): TList<string>;
  protected
    function GetControllerMappedPath(
      const aControllerName: string;
      const aControllerAttributes: TArray<TCustomAttribute>): string;
  public
    class function StringMethodToHTTPMetod(const aValue: string): TMVCHTTPMethodType; static;
    constructor Create(const aConfig: TMVCConfig;
      const aActionParamsCache: TMVCStringObjectDictionary<TMVCActionParamCacheItem>);
    destructor Destroy; override;
    function ExecuteRouting(
      const ARequestPathInfo: string;
      const ARequestMethodType: TMVCHTTPMethodType;
      const ARequestContentType: string;
      const ARequestAccept: string;
      const AControllers: TObjectList<TMVCControllerDelegate>;
      const ADefaultContentType: string;
      const ADefaultContentCharset: string;
      var ARequestParams: TMVCRequestParamsTable;
      out AResponseContentMediaType: string;
      out AResponseContentCharset: string): Boolean;
    function GetQualifiedActionName: string; override;

    property MethodToCall: TRttiMethod read FMethodToCall;
    property ControllerClazz: TMVCControllerClazz read FControllerClazz;
    property ControllerCreateAction: TMVCControllerCreateAction read FControllerCreateAction;
  end;

implementation

uses
  System.TypInfo;

{ TMVCRouter }

constructor TMVCRouter.Create(const aConfig: TMVCConfig;
  const aActionParamsCache: TMVCStringObjectDictionary<TMVCActionParamCacheItem>);
begin
  inherited Create;
  FRttiContext := TRttiContext.Create;
  FConfig := aConfig;
  FMethodToCall := nil;
  FControllerClazz := nil;
  FControllerCreateAction := nil;
  FActionParamsCache := aActionParamsCache;
end;

destructor TMVCRouter.Destroy;
begin
  FRttiContext.Free;
  inherited Destroy;
end;

function TMVCRouter.ExecuteRouting(const ARequestPathInfo: string;
  const ARequestMethodType: TMVCHTTPMethodType;
  const ARequestContentType, ARequestAccept: string;
  const AControllers: TObjectList<TMVCControllerDelegate>;
  const ADefaultContentType: string;
  const ADefaultContentCharset: string;
  var ARequestParams: TMVCRequestParamsTable;
  out AResponseContentMediaType: string;
  out AResponseContentCharset: string): Boolean;
var
  LRequestPathInfo: string;
  LRequestAccept: string;
  LRequestContentType: string;
  LControllerMappedPath: string;
  LControllerDelegate: TMVCControllerDelegate;
  LAttributes: TArray<TCustomAttribute>;
  LAtt: TCustomAttribute;
  LRttiType: TRttiType;
  LMethods: TArray<TRttiMethod>;
  LMethod: TRttiMethod;
  LMethodPath: string;
  LProduceAttribute: MVCProducesAttribute;
  lPathPrefix: string;
  lURLSegment: string;
  // JUST FOR DEBUG
  // lMethodCompatible: Boolean;
  // lContentTypeCompatible: Boolean;
  // lAcceptCompatible: Boolean;
begin
  Result := False;

  FMethodToCall := nil;
  FControllerClazz := nil;
  FControllerCreateAction := nil;

  LRequestAccept := ARequestAccept;
  LRequestContentType := ARequestContentType;
  LRequestPathInfo := ARequestPathInfo;
  if (Trim(LRequestPathInfo) = EmptyStr) then
    LRequestPathInfo := '/'
  else
  begin
    if not LRequestPathInfo.StartsWith('/') then
    begin
      LRequestPathInfo := '/' + LRequestPathInfo;
    end;
  end;
  LRequestPathInfo := TIdURI.PathEncode(LRequestPathInfo);

  lPathPrefix := FConfig.Value[TMVCConfigKey.PathPrefix];

  TMonitor.Enter(gLock);
  try
    LControllerMappedPath := EmptyStr;
    for LControllerDelegate in AControllers do
    begin
      SetLength(LAttributes, 0);
      LRttiType := FRttiContext.GetType(LControllerDelegate.Clazz.ClassInfo);

      lURLSegment := LControllerDelegate.URLSegment;
      if lURLSegment.IsEmpty then
      begin
        LAttributes := LRttiType.GetAttributes;
        if (LAttributes = nil) then
          Continue;
        LControllerMappedPath := GetControllerMappedPath(LRttiType.Name, LAttributes);
      end
      else
      begin
        LControllerMappedPath := lURLSegment;
      end;

      if (LControllerMappedPath = '/') then
      begin
        LControllerMappedPath := '';
      end;

      if not LRequestPathInfo.StartsWith(lPathPrefix + LControllerMappedPath, True) then
      begin
        Continue;
      end;

      LMethods := LRttiType.GetMethods; { do not use GetDeclaredMethods because JSON-RPC rely on this!! }
      for LMethod in LMethods do
      begin
        if LMethod.Visibility <> mvPublic then // 2020-08-08
          Continue;
        if (LMethod.MethodKind <> mkProcedure) { or LMethod.IsClassMethod } then
          Continue;

        LAttributes := LMethod.GetAttributes;
        if Length(LAttributes) = 0 then
          Continue;

        for LAtt in LAttributes do
        begin
          if LAtt is MVCPathAttribute then
          begin
            // THIS BLOCK IS HERE JUST FOR DEBUG
            // if LMethod.Name.Contains('GetProject') then
            // begin
            // lMethodCompatible := True; //debug here
            // end;
            // lMethodCompatible := IsHTTPMethodCompatible(ARequestMethodType, LAttributes);
            // lContentTypeCompatible := IsHTTPContentTypeCompatible(ARequestMethodType, LRequestContentType, LAttributes);
            // lAcceptCompatible :=  IsHTTPAcceptCompatible(ARequestMethodType, LRequestAccept, LAttributes);

            if IsHTTPMethodCompatible(ARequestMethodType, LAttributes) and
              IsHTTPContentTypeCompatible(ARequestMethodType, LRequestContentType, LAttributes) and
              IsHTTPAcceptCompatible(ARequestMethodType, LRequestAccept, LAttributes) then
            begin
              LMethodPath := MVCPathAttribute(LAtt).Path;
              if IsCompatiblePath(lPathPrefix + LControllerMappedPath + LMethodPath,
                LRequestPathInfo, ARequestParams) then
              begin
                FMethodToCall := LMethod;
                FControllerClazz := LControllerDelegate.Clazz;
                FControllerCreateAction := LControllerDelegate.CreateAction;
                LProduceAttribute := GetAttribute<MVCProducesAttribute>(LAttributes);
                if LProduceAttribute <> nil then
                begin
                  AResponseContentMediaType := LProduceAttribute.Value;
                  AResponseContentCharset := LProduceAttribute.Charset;
                end
                else
                begin
                  AResponseContentMediaType := ADefaultContentType;
                  AResponseContentCharset := ADefaultContentCharset;
                end;
                Exit(True);
              end;
            end;
          end; // if MVCPathAttribute
        end; // for in Attributes
      end; // for in Methods
    end; // for in Controllers
  finally
    TMonitor.Exit(gLock);
  end;
end;

function TMVCRouter.GetAttribute<T>(const AAttributes: TArray<TCustomAttribute>): T;
var
  Att: TCustomAttribute;
begin
  Result := nil;
  for Att in AAttributes do
    if Att is T then
      Exit(T(Att));
end;

function TMVCRouter.GetControllerMappedPath(
  const aControllerName: string;
  const aControllerAttributes: TArray<TCustomAttribute>): string;
var
  LFound: Boolean;
  LAtt: TCustomAttribute;
begin
  LFound := False;
  for LAtt in aControllerAttributes do
  begin
    if LAtt is MVCPathAttribute then
    begin
      LFound := True;
      Result := MVCPathAttribute(LAtt).Path;
      Break;
    end;
  end;

  if not LFound then
    raise EMVCException.CreateFmt('Controller %s does not have MVCPath attribute', [aControllerName]);
end;

function TMVCRouter.GetFirstMediaType(const AContentType: string): string;
begin
  Result := AContentType;
  while Pos(',', Result) > 0 do
    Result := Copy(Result, 1, Pos(',', Result) - 1);
  while Pos(';', Result) > 0 do
    Result := Copy(Result, 1, Pos(';', Result) - 1);
end;

function TMVCRouter.IsCompatiblePath(
  const AMVCPath: string;
  const APath: string;
  var aParams: TMVCRequestParamsTable): Boolean;

  function ToPattern(const V: string; const Names: TList<string>): string;
  var
    S: string;
  begin
    Result := V;
    for S in Names do
      Result := StringReplace(Result, '($' + S + ')', '([' + TMVCConstants.URL_MAPPED_PARAMS_ALLOWED_CHARS + ']*)',
        [rfReplaceAll]);
  end;

var
  lRegEx: TRegEx;
  lMatch: TMatch;
  lPattern: string;
  I: Integer;
  lNames: TList<string>;
  lCacheItem: TMVCActionParamCacheItem;
begin
  if not FActionParamsCache.TryGetValue(AMVCPath, lCacheItem) then
  begin
    lNames := GetParametersNames(AMVCPath);
    lPattern := ToPattern(AMVCPath, lNames);
    lCacheItem := TMVCActionParamCacheItem.Create(lPattern, lNames);
    FActionParamsCache.Add(AMVCPath, lCacheItem);
  end;

  if (APath = AMVCPath) then
    Exit(True)
  else
  begin
    lRegEx := TRegEx.Create('^' + lCacheItem.Value + '$', [roIgnoreCase, roCompiled, roSingleLine]);
    lMatch := lRegEx.match(APath);
    Result := lMatch.Success;
    if Result then
    begin
      for I := 1 to pred(lMatch.Groups.Count) do
      begin
        aParams.Add(lCacheItem.Params[I - 1], TIdURI.URLDecode(lMatch.Groups[I].Value));
      end;
    end;
  end;
end;

function TMVCRouter.GetParametersNames(const V: string): TList<string>;
var
  S: string;
  Matches: TMatchCollection;
  M: TMatch;
  I: Integer;
  lList: TList<string>;
begin
  lList := TList<string>.Create;
  try
    S := '\(\$([A-Za-z0-9\_]+)\)';
    Matches := TRegEx.Matches(V, S, [roIgnoreCase, roCompiled, roSingleLine]);
    for M in Matches do
    begin
      for I := 0 to M.Groups.Count - 1 do
      begin
        S := M.Groups[I].Value;
        if (Length(S) > 0) and (S.Chars[0] <> '(') then
        begin
          lList.Add(S);
          Break;
        end;
      end;
    end;
    Result := lList;
  except
    lList.Free;
    raise;
  end;
end;

function TMVCRouter.GetQualifiedActionName: string;
begin
  Result := Self.FControllerClazz.QualifiedClassName + '.' + Self.MethodToCall.Name;
end;

function TMVCRouter.IsHTTPAcceptCompatible(
  const ARequestMethodType: TMVCHTTPMethodType;
  var AAccept: string;
  const AAttributes: TArray<TCustomAttribute>): Boolean;
var
  I: Integer;
  MethodAccept: string;
  FoundOneAttProduces: Boolean;
begin
  Result := False;
  if AAccept.Contains('*/*') then // 2020-08-08
  begin
    Exit(True);
  end;

  FoundOneAttProduces := False;
  for I := 0 to high(AAttributes) do
    if AAttributes[I] is MVCProducesAttribute then
    begin
      FoundOneAttProduces := True;
      MethodAccept := MVCProducesAttribute(AAttributes[I]).Value;
      AAccept := GetFirstMediaType(AAccept);
      Result := SameText(AAccept, MethodAccept, loInvariantLocale);
      if Result then
        Break;
    end;

  Result := (not FoundOneAttProduces) or (FoundOneAttProduces and Result);
end;

function TMVCRouter.IsHTTPContentTypeCompatible(
  const ARequestMethodType: TMVCHTTPMethodType;
  var AContentType: string;
  const AAttributes: TArray<TCustomAttribute>): Boolean;
var
  I: Integer;
  MethodContentType: string;
  FoundOneAttConsumes: Boolean;
begin
  if ARequestMethodType in MVC_HTTP_METHODS_WITHOUT_CONTENT then
    Exit(True);

  Result := False;

  FoundOneAttConsumes := False;
  for I := 0 to high(AAttributes) do
    if AAttributes[I] is MVCConsumesAttribute then
    begin
      FoundOneAttConsumes := True;
      MethodContentType := MVCConsumesAttribute(AAttributes[I]).Value;
      AContentType := GetFirstMediaType(AContentType);
      Result := SameText(AContentType, MethodContentType, loInvariantLocale);
      if Result then
        Break;
    end;

  Result := (not FoundOneAttConsumes) or (FoundOneAttConsumes and Result);
end;

function TMVCRouter.IsHTTPMethodCompatible(
  const AMethodType: TMVCHTTPMethodType;
  const AAttributes: TArray<TCustomAttribute>): Boolean;
var
  I: Integer;
  MustBeCompatible: Boolean;
  CompatibleMethods: TMVCHTTPMethods;
begin
  Result := False;

  MustBeCompatible := False;
  for I := 0 to high(AAttributes) do
    if AAttributes[I] is MVCHTTPMethodAttribute then
    begin
      MustBeCompatible := True;
      CompatibleMethods := MVCHTTPMethodAttribute(AAttributes[I]).MVCHTTPMethods;
      Result := (AMethodType in CompatibleMethods);
    end;

  Result := (not MustBeCompatible) or (MustBeCompatible and Result);
end;

class function TMVCRouter.StringMethodToHTTPMetod(const aValue: string): TMVCHTTPMethodType;
begin
  if aValue = 'GET' then
    Exit(httpGET);
  if aValue = 'POST' then
    Exit(httpPOST);
  if aValue = 'DELETE' then
    Exit(httpDELETE);
  if aValue = 'PUT' then
    Exit(httpPUT);
  if aValue = 'HEAD' then
    Exit(httpHEAD);
  if aValue = 'OPTIONS' then
    Exit(httpOPTIONS);
  if aValue = 'PATCH' then
    Exit(httpPATCH);
  if aValue = 'TRACE' then
    Exit(httpTRACE);
  raise EMVCException.CreateFmt('Unknown HTTP method [%s]', [aValue]);
end;

{ TMVCActionParamCacheItem }

constructor TMVCActionParamCacheItem.Create(aValue: string;
  aParams: TList<string>);
begin
  inherited Create;
  FValue := aValue;
  FParams := aParams;
end;

destructor TMVCActionParamCacheItem.Destroy;
begin
  FParams.Free;
  inherited;
end;

function TMVCActionParamCacheItem.Params: TList<string>;
begin
  Result := FParams;
end;

function TMVCActionParamCacheItem.Value: string;
begin
  Result := FValue;
end;

end.
