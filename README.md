# MATLAB struct data serialization for generated code

Support run-time data saving and loading in the generated code to simplify tricky wrapper calls to low-level functions such as `fread`, `fwrite`, etc. Comparable performance and storage size with commonly used C++ open source serialization libraries (e.g. [boost.Serialization](https://www.boost.org/doc/libs/1_82_0/libs/serialization/doc/index.html),[Cereal](http://uscilab.github.io/cereal/index.html), etc.).

----
 在生成的代码中支持运行时刻的数据保存和加载，以简化`fread`,`fwrite`等低等级函数的棘手包装调用。与常用的C++开源序列化库（比如[boost.Serialization](https://www.boost.org/doc/libs/1_82_0/libs/serialization/doc/index.html),[Cereal](http://uscilab.github.io/cereal/index.html)等）有可比较的性能和存储大小。

## Features And Limitions

- Support for scalar structure and arrays of structures
- Support any level of nesting of structures or arrays
- Support for structure field value base types, `'double', 'single', 'int8', 'int16', 'int32', 'int64', 'uint8', 'uint16', 'uint32', 'uint64', 'logical', 'char', 'string', ' struct'`
- The sub-field of a structure or an array supports at most 3-dimensional arrays
- The field type of a structure or array with the same field name should be consistent

## Compare matlab build-in functions

some build-in functions:

- `coder.read`,read data files at run time in generated code,it can support C/C++ code generation
- `coder.write`,write data files that the generated code reads at run time,current R2023a it doesn't support C/C++ code generation
- `coder.load`, only load MAT-file or ASCII file,doesn't support generated code at run time
- `load`,only load MAT-file or ASCII file,doesn't support generated code at run time
- `readstruct`,current only support read structure from "xml" file,it doesn't support generated code at run time
- `writestruct`,current only support write matlab structure to "xml" file,it doesn't support generated code at run time

this project functions

- `readStructBin`,read data files at run time in generated code,current it doesn't support C/C++ generation
- `writeStructBin`,write data files that the generated code reads at run time,it support C/C++ generation

## Syntax

writeStructBin:

```matlab
writeStructBin(S);
writeStructBin(S,configFileName,binaryFileName);
```

readStructBin:

```matlab
S = readStructBin(configFileName,binaryFileName)
```

## Example

For example, to save the structure `S1` to the "data.cfg" and "data.stdata" files in the current working directory. The structure `S1` fields has four types of parameters: "a", "b", "c", "d", and the sub-field "c" is actually a nested structure with three field names: "A", "B", and "C":

```matlab
S1 = struct("a",1,...
"b",rand(1,3),...
"c",struct("A",[1,2],"B",'matlab_coder',"C",rand(5,2)),...
"d",uint8([15,123]));
```

Then define the description file `configFileName` and the binary file name `binaryFileName` that needs to be saved, the two names are preferably the same except for the suffix, the purpose is to match the subsequent consistency and avoid wrong reads.

```matlab
configFileName = "data.cfg";% Available for manual reading
binaryFileName = "data.stdata";
writeStructBin(S1,configFileName,binaryFileName);
```

After a successful write to the file, then execute  `readStructBin` function.

```matlab
S2 = readStructBin(configFileName,binaryFileName);
```

After successfully reading in the file, you can find that `S1` and `S2` results are the same!
