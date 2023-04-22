function  S = readStructBin(configFileName,binaryFileName)% 暂时还不支持C/C++代码生成！！！请参阅https://www.mathworks.com/matlabcentral/answers/1948868-non-constant-expression-or-empty-matrix-this-expression-must-be-constant-because-its-value-determin
% Brief: 对二进制文件反序列化(读取)为结构体/数组S,弥补coder.read/coder.write不同时支持运行时刻的C/C++代码生成
% Details:
%    对指定的二进制文件configFileName(通常后缀为.cfg的描述文件),binaryFileName(通常后缀为.stdata的二进制文件)反序列化(读取) 为结构体/数组S.
%
% Notes:
%     1.本函数需与writeStructBin函数匹配使用，即只能读取writeStructBin函数输出的二进制文件.
%     
%
% Syntax:
%      S = readStructBin(configFileName,binaryFileName)
%
% Inputs:
%    configFileName - [1,:] size,[char] type,存储的描述文件名，字符向量或者单个字符串，后缀最好以.cfg结尾
%    binaryFileName - [1,:] size,[char] type,存储的二进制文件名，字符向量或者单个字符串，后缀最好以.stdata结尾
%
% Outputs:
%    S - [:,:] size,[struct] type,反序列化(读取)的结构体或者数组
%
% Example:
%   configFileName = "./data.cfg";
%   binaryFileName = "./data.stdata";
%   S1 = struct("a",1,"b",rand(1,3),"c",struct("A",[1,2],"B",'matlab_coder',"C",rand(5,2)),"d",uint8([15,123]));
%   S2 = struct("a",10,"b",rand(3,3),"c",struct("A",[5,6],"B",'matlab',"C",rand(10,2)),"d",uint8([10,200;50,32]));
%   S = [S1,S2];
%   writeStructBin(S,configFileName,binaryFileName);
%   M = readStructBin(configFileName,binaryFileName);% M与S验证结果一致
%
% codegen example command:  
%   cfg = "data.cfg";
%   cfg = coder.typeof(cfg);
%   cfg.StringLength=255;
%   cfg.VariableStringLength=true;
%   datast = cfg;
%   codegen -config:mex readStructBin -args {cfg,datast} -lang:c++ -report
%
%
% See also: writeStructBin,coder.read,coder.write,writestruct,readstruct

% Author:                          cuixingxing
% Email:                           cuixingxing150@gmail.com
% Created:                         14-Apr-2023 15:16:02
% Version history revision notes:
%                                  None
% Implementation In Matlab R2023a
%

% 算法思路：
% 由于当前MATLAB的C/C++代码生成器不支持字符串"左值"转可执行语句和结构体域名动态赋值，故设计如下逆向思维的"泛型算法"：
%
% step1,比如有以下结构体数组S：
%   S1 = struct("a",1,"b",rand(1,3),"c",struct("A",[1,2],"B",'cuixing',"C",rand(5,2)),"d",uint8([15,123]));
%   S2 = struct("a",10,"b",rand(3,3),"c",struct("A",[5,6],"B",'matlab',"C",rand(10,2)),"d",uint8([10,200;50,32]));
%   S = [S1,S2];
%   writeStructBin(S)
% 成功保存为二进制文件后，然后设计读取描述文件configFileName所有行，并统计为3组cell，分别如下所示：
% 域名cell: {{S},{S.a,S.b,S.c},{S.c.A,S.c.B,S.c.C}}
% 大小cell: {{[h,w,c]},{[h1,w1,c1],[h2,w2,c2],[h3,w3,c3]},{...}}
% 类型cell: {{tyename1},{typename2,typename3,typename4},{...}}
% 上述3组cell中元素一一对应，从父级逐渐过渡到子级域;
% step2: 从子级域向父级域逐级赋初值，按照同级别同名域的最大容纳数组进行填充，目的方便步骤3的直接迭代索引进行赋读取的真值;
% step3: 重新读取描述文件中每个域的实际大小，然后配合读取的二进制文件进行赋真值;
% step4: 算法结束。
%

arguments
    configFileName (1,:) char
    binaryFileName (1,:) char
end
configFid = fopen(configFileName,"r");
if configFid == -1
    error('Error. \nCan''t open this file: %s.',configFileName)	% fopen failed
end
dataFid = fopen(binaryFileName,"r");
if dataFid == -1
    error('Error. \nCan''t open this file: %s.',binaryFileName)	% fopen failed
end
fileCloserCfg = onCleanup(@()(safeFclose(configFid)));
fileCloserData = onCleanup(@()(safeFclose(dataFid)));

%% step1:fieldLevelNames，fieldLevelSizes，fieldLevelTypes三组对应的cell
% 目的用于获取预先定义的变量大小和类型示例，以便用于C/C++代码生成使用
numLevel = 1;
while ~feof(configFid)
    tline = fgetl(configFid);
    idxDot = strfind(tline,'.');
    numDot = numel(idxDot);% 判读域名的级别
    numLevel = max(numDot+1,numLevel);
end
fieldLevelNames = cell(1,numLevel);
fieldLevelSizes = cell(1,numLevel);
fieldLevelTypes = cell(1,numLevel);
for row = 1:numLevel
    fieldLevelNames{row} = cell(1,0);
    fieldLevelSizes{row} = cell(1,0);
    fieldLevelTypes{row} = cell(1,0);
end
% coder.const(configFileName);
% metaData = coder.const(@feval, 'getMetadataFromConfig', char(configFileName));

frewind(configFid);% move to the beginning of a file
while ~feof(configFid)
    tline = fgetl(configFid);
    tline = eraseBetween(tline,'(',')','Boundaries','inclusive');

    pat1 = '=';
    pat2 = '*';
    pat3 = ',';
    idxEqual = strfind(tline,pat1);
    idxMultiply = strfind(tline,pat2);
    idxComma =strfind(tline,pat3);
    assert(numel(idxEqual)==1&&numel(idxMultiply)==2&&numel(idxComma)==1);
    idxEqual = idxEqual(1);
    idxComma = idxComma(1);

    iterVarName = tline(1:idxEqual-1);
    hStr = tline(idxEqual+1:idxMultiply(1)-1);
    wStr = tline(idxMultiply(1)+1:idxMultiply(2)-1);
    cStr = tline(idxMultiply(2)+1:idxComma-1);
    iterVarSize = [real(str2double(hStr)),real(str2double(wStr)),real(str2double(cStr))];% note:str2double,Generated code always returns a complex result.
    iterVarType = tline(idxComma+1:end);

    % 为上述3个数组cell填充
    idxDot = strfind(tline,'.');
    numDot = numel(idxDot);% 判读域名的级别
    levelID = numDot+1;
    if numel(fieldLevelNames)<levelID % fieldLevelNames不存在该level的域名
        fieldLevelNames{levelID} = {iterVarName};
        fieldLevelSizes{levelID} = {iterVarSize};
        fieldLevelTypes{levelID} = {iterVarType};
    end

    % 判断同级域名是否重名/已存在，不存在就增加该级别的域名，存在就合并（大小和类型）
    [flag,Locb] = ismemberN(iterVarName,fieldLevelNames{levelID});
    if flag
        previousSizes = fieldLevelSizes{levelID}{Locb};
        currentSizes = iterVarSize;
        mergeSizes = max(previousSizes,currentSizes);
        fieldLevelSizes{levelID}{Locb} = mergeSizes;
        mergeType = fieldLevelTypes{levelID}{Locb};
        assert(strcmpi(mergeType,iterVarType),"merge type must be consistent!");
    else
        currLevelNames = fieldLevelNames{levelID};
        currLevelSizes = fieldLevelSizes{levelID};
        currLevelTypes = fieldLevelTypes{levelID};
        currLevelNames{end+1} = iterVarName;
        currLevelSizes{end+1} = iterVarSize;
        currLevelTypes{end+1} = iterVarType;

        fieldLevelNames{levelID} = currLevelNames;
        fieldLevelSizes{levelID} = currLevelSizes;
        fieldLevelTypes{levelID} = currLevelTypes;
    end
end

%% step2: 逆序实例化S的每个field，目的在于预分配数据，方便后续索引支持操作
preLevelParentSt = struct();
numsLevel = numel(fieldLevelNames);
for row = numsLevel:-1:1 
    currLevelParentSt = struct();
    currLevelFieldsNames = fieldLevelNames{row};
    % 实例化每个level下的基础类型field
    [~,currFieldNodeName,~] = parseNodeName(currLevelFieldsNames{1});
    if row>1 
        temp = struct();
        numsFields = numel(currLevelFieldsNames);
        for col = 1:numsFields
            if coder.target("MATLAB")
                [~,~,sonFieldNodeName] = parseNodeName(currLevelFieldsNames{col});
            else % https://www.mathworks.com/matlabcentral/answers/1948868-non-constant-expression-or-empty-matrix-this-expression-must-be-constant-because-its-value-determin
                fprintf('Looking forward to implementing...\n');
            end
            if strcmpi(fieldLevelTypes{row}{col},'char')||strcmpi(fieldLevelTypes{row}{col},'string')
                temp.(sonFieldNodeName) = repmat('?',fieldLevelSizes{row}{col});
            elseif strcmpi(fieldLevelTypes{row}{col},'struct') % ie. numsLevel>2
                st = preLevelParentSt.(sonFieldNodeName);
                temp.(sonFieldNodeName) = repmat(st,fieldLevelSizes{row}{col});
            else
                temp.(sonFieldNodeName) = zeros(fieldLevelSizes{row}{col},fieldLevelTypes{row}{col});
            end
        end
        currLevelParentSt.(currFieldNodeName) = temp;
        if row==2 % 即S.a,S.b,...形式，此时parentFieldNodeName为未定义的"undefinedParentNode"的变量
            S = temp;
        end
    else % row ==1 ,即只有S，此时parentFieldNodeName和sonFieldNodeName分别为未定义的"undefinedParentNode","undefinedSonNode"变量
        S = repmat(S,fieldLevelSizes{1}{1});
    end
    preLevelParentSt = currLevelParentSt;
end

%% step3,读取二进制数据赋值给S
frewind(configFid);% move to the beginning of a file
S = iterReadBinFile(configFid,dataFid,S);
end

%% suport functions
function [flag,Locb] = ismemberN(item,B)
% 功能等同于ismember,以支持C/C++代码生成,item为字符向量,B为含字符向量的元胞数组
flag = false;
Locb = [];
for row = 1:numel(B)
    if strcmpi(item,B{row})
        flag = true;
        Locb = row;
    end
end
end

function [parentFieldNodeName,currFieldNodeName,sonFieldNodeName] = parseNodeName(fieldName)
idxDots = strfind(fieldName,'.');
if numel(idxDots)>1
    if numel(idxDots)>2
        startIdx = idxDots(end-1)+1;
        stopIdx = idxDots(end)-1;
        currFieldNodeName = fieldName(startIdx:stopIdx);
        startIdx = idxDots(end)+1;
        sonFieldNodeName = fieldName(startIdx:end);
        startIdx = idxDots(end-2)+1;
        stopIdx = idxDots(end-1)-1;
        parentFieldNodeName = fieldName(startIdx:stopIdx);

    else
        startIdx = idxDots(end-1)+1;
        stopIdx = idxDots(end)-1;
        currFieldNodeName = fieldName(startIdx:stopIdx);
        startIdx = idxDots(end)+1;
        sonFieldNodeName = fieldName(startIdx:end);
        startIdx = 1;
        stopIdx = idxDots(end-1)-1;
        parentFieldNodeName = fieldName(startIdx:stopIdx);
    end
elseif numel(idxDots)==1
    idxDots = idxDots(1);
    parentFieldNodeName = 'undefinedParentNode';
    currFieldNodeName = fieldName(1:idxDots-1);
    sonFieldNodeName = fieldName(idxDots+1:end);
else
    parentFieldNodeName = 'undefinedParentNode';
    currFieldNodeName = fieldName;
    sonFieldNodeName = 'undefinedSonNode';
end
end

function backTrackVar = iterReadBinFile(configFid,dataFid,backTrackVar)%#codegen
% 参考writeStructBin.m中子函数iterWriteBinFile改写，必须一一对应才能正确读入
% note:logical type is default 'uint8'
baseSupportClass =  {'double','single','int8','int16','int32','int64',...
    'uint8','uint16','uint32','uint64','logical', 'char','string'};

[h,w,c] = size(backTrackVar);
typeName = class(backTrackVar);

tline = fgetl(configFid);
tline = eraseBetween(tline,'(',')','Boundaries','inclusive');

pat1 = '=';
pat2 = '*';
pat3 = ',';
idxEqual = strfind(tline,pat1);
idxMultiply = strfind(tline,pat2);
idxComma =strfind(tline,pat3);
assert(numel(idxEqual)==1&&numel(idxMultiply)==2&&numel(idxComma)==1);

hStr = tline(idxEqual+1:idxMultiply(1)-1);
wStr = tline(idxMultiply(1)+1:idxMultiply(2)-1);
cStr = tline(idxMultiply(2)+1:idxComma-1);
iterVarSize = [str2double(hStr),str2double(wStr),str2double(cStr)];
iterVarType = tline(idxComma+1:end);


if matches(iterVarType,baseSupportClass)
    numsEle = prod(iterVarSize,"all");
    if matches(typeName,'string')
        backTrackVar = fread(dataFid,numsEle,'char=>char');
        backTrackVar = reshape(backTrackVar,iterVarSize);
        backTrackVar = string(backTrackVar);
    elseif matches(typeName,'logical')
        backTrackVar = fread(dataFid,numsEle,'uint8=>logical');
        backTrackVar = reshape(backTrackVar,iterVarSize);
    else
        backTrackVar = fread(dataFid,numsEle,[typeName,'=>',typeName]);
        backTrackVar = reshape(backTrackVar,iterVarSize);
    end
elseif isstruct(backTrackVar)
    if h*w*c==1
        backTrackVar = backTrackVar(h,w,c);
        fields = fieldnames(backTrackVar);
        numFields = numel(fields);
        for row = 1:numFields
            currVar = backTrackVar.(fields{row});
            backTrackVar.(fields{row}) = iterReadBinFile(configFid,dataFid,currVar);
        end
    else
        for row = 1:h
            for col = 1:w
                for k =1:c
                    currVar = backTrackVar(row,col,k);
                    backTrackVar(row,col,k) = iterReadBinFile(configFid,dataFid,currVar);
                end
            end
        end
    end
else
    error('prog:input','unsupport type:%s.',typeName);
end
end

function safeFclose(fid)
coder.inline('always')
if fid ~=-1
    fclose(fid);
end
end