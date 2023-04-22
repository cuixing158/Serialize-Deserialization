function  writeStructBin(S,configFileName,binaryFileName)%#codegen
% Brief: 对结构体/数组S序列化(保存)为二进制文件,弥补coder.read/coder.write不同时支持运行时刻的C/C++代码生成
% Details:
%    为结构体/数组S指定存储为名configname后缀为.cfg的描述文件，binaryname后缀为.stdata的二进制数据文件,为便于使用,两者名字最好匹配一致.
%
% Notes:
%     1.结构体/数组S的子域支持类型为:'double','single','int8','int16','int32','int64','uint8','uint16','uint32','uint64','logical',
%     'char','string','struct',暂时不支持cell;
%     2.结构体/数组S的子域最多支持不超过3维数组;
%     3.结构体/数组S同名的域类型要保持一致.
%
% Syntax:
%      writeStructBin(S);
%      writeStructBin(S,configFileName,binaryFileName);
%
% Inputs:
%    S - [:,:] size,[struct] type,要序列化(保存)的结构体或者数组
%    configFileName - [1,:] size,[char] type,存储的描述文件名，字符向量或者单个字符串，后缀最好以.cfg结尾
%    binaryFileName - [1,:] size,[char] type,存储的二进制文件名，字符向量或者单个字符串，后缀最好以.stdata结尾
%
%
% Example:
%   S1 = struct("a",1,"b",rand(1,3),"c",struct("A",[1,2],"B",'matlab_coder',"C",rand(5,2)),"d",uint8([15,123]));
%   S2 = struct("a",10,"b",rand(3,3),"c",struct("A",[5,6],"B",'matlab',"C",rand(10,2)),"d",uint8([10,200;50,32]));
%   S = [S1,S2];
%   configFileName = "./data.cfg";
%   binaryFileName = "./data.stdata";
%   writeStructBin(S,configFileName,binaryFileName)
%
% codegen example command:
%    % S = struct("a",1,"b",rand(1,3),"c",struct("A",[1,2],"B",'aaa',"C",rand(5,2)),"d",uint8([15,123]));
%   var1 = coder.typeof(double(0),[inf,3]);
%   var2 = coder.typeof(char(0),[1,inf]);
%   var3 = coder.typeof(double(0),[inf,2]);
%   var4 = coder.typeof(uint8(0),[inf,2]);
%   S = struct("a",1,"b",var1,"c",struct("A",[1,2],"B",var2,"C",var3),"d",var4);
%   S = coder.typeof(S,[1,inf]);
%   
%   cfg = "data.cfg";
%   cfg = coder.typeof(cfg);
%   cfg.StringLength=255;
%   cfg.VariableStringLength=true;
%   datast = cfg;
%   codegen -config:mex writeStructBin -args {S,cfg,datast} -lang:c++ -report
%
% See also: readStructBin,coder.read,coder.write,writestruct,readstruct

% Author:                          cuixingxing
% Email:                           cuixingxing150@gmail.com
% Created:                         14-Apr-2023 07:58:17
% Version history revision notes:
%                                  None
% Implementation In Matlab R2023a
%

arguments
    S (:,:) struct
    configFileName (1,:) char = "data.cfg" % or use string scalar
    binaryFileName (1,:) char = "data.stdata" % or use string scalar
end


configFid = fopen(configFileName,"w");
if configFid == -1
	error('Error. \nCan''t open this file: %s.',configFileName)	% fopen failed
end
dataFid = fopen(binaryFileName,"w");
if dataFid == -1
	error('Error. \nCan''t open this file: %s.',binaryFileName)	% fopen failed
end
fileCloserCfg = onCleanup(@()(safeFclose(configFid)));
fileCloserData = onCleanup(@()(safeFclose(dataFid)));

% recursion iteration
iterVar = S;
iterVarName = 'S';
iterWriteBinFile(configFid,dataFid,iterVar,iterVarName);
end

function iterWriteBinFile(configFid,dataFid,iterVar,iterVarName)%#codegen
% note:logical type is default 'uint8'
baseSupportClass =  {'double','single','int8','int16','int32','int64',...
    'uint8','uint16','uint32','uint64','logical', 'char','string'};

assert(ndims(iterVar)<=3);% current support at most 3 dims
if isstring(iterVar)
    assert(isscalar(iterVar),'string must be a scalar.')
    iterVar = char(iterVar);
end

[h,w,c] = size(iterVar); 
typeName = class(iterVar);

fprintf(configFid,"%s=%d*%d*%d,%s\n",iterVarName,int32(h),int32(w),int32(c),typeName);


if matches(typeName,baseSupportClass)
    if matches(typeName,{'char','string'})
        fwrite(dataFid,char(iterVar),'char');
    elseif matches(typeName,'logical')
        fwrite(dataFid,iterVar,'uint8');
    else
        fwrite(dataFid,iterVar,typeName);
    end
elseif isstruct(iterVar)
    if h*w*c==1
        iterVar = iterVar(h,w,c);
        fields = fieldnames(iterVar);
        numFields = numel(fields);
        for i = 1:numFields
            currVar = iterVar.(fields{i});
            currVarName = [iterVarName,'.',fields{i}];
            iterWriteBinFile(configFid,dataFid,currVar,currVarName);
        end
    else
        for i = 1:h
            for j = 1:w
                for k =1:c
                    currVar = iterVar(i,j,k);
                    currVarName = sprintf('%s(%d,%d,%d)',iterVarName,int32(i),int32(j),int32(k));
                    iterWriteBinFile(configFid,dataFid,currVar,currVarName);
                end
            end
        end
    end
else
    error('prog:input','unsupport field:%s,type:%s.',iterVarName,typeName);
end
end

function safeFclose(fid)
coder.inline('always')
if fid ~=-1
    fclose(fid);
end
end