function [ out ] = importDTSFolder( folderpath )
%importDTSFolder Import the contents of a DTS binary file folder
%   Import the top-level folder containing the DTS binary contents of a test.
%   The top-level folder contains a '.dts' file containing the metadata of a
%   test and a number of '.chn' files containing the binary contents of test.
%   The resulting output is a struture containing the 'meta' and 'contents'.
%
%   The 'meta' field is a array of structures where each structure corresponds
%   to the contents of each XML structure contained in the '.dts' file. The 
%   structure is defined in makeDTSMetaNode
%
%   The 'containers' field is a containers.Map where each key corresponds to the
%   filename of the '.chn' file and the value is a structure of the file
%   contents described in makeDTSCHNContents
%
%   Mike Tegtmeyer 
%   Army Research Laboratory
%   (michael.b.tegtmeyer.civ@mail.mil)

out = struct( ...
  'meta',[], ...
  'contents',containers.Map('KeyType','char','ValueType','any'));


if ~isdir(folderpath)
  ex = MException('importDTSFolder:badPath', ...
    'Error: path "%s" is not top-level DTS data directory',folderpath);
  throwAsCaller(ex);
end

dtsFileInfo = dir([folderpath filesep '*.dts']);
if isempty(dtsFileInfo)
  ex = MException('importDTSFolder:badPath', ...
    'Error: path "%s" is given as a top-level DTS data directory but no ".dts" file is found.',folderpath);
  throwAsCaller(ex);
elseif length(dtsFileInfo) > 1
  ex = MException('importDTSFolder:badPath', ...
    'Error: unexpected multiple ".dts" files were found in the given DTS top-level data directory "%s"',folderpath);
  throwAsCaller(ex);
end

dtsFilePath = [folderpath filesep dtsFileInfo(1).name];
out.meta = readDTSFile(dtsFilePath);

verifyDTSTopFileMeta(out.meta);

% read the .chn files, this really should be smarter, ie we read the filenames
% based on what is contained in the metadata. Since it isn't clear right now how
% that is supposed to work correctly, simply read in all the .chn files and
% insert them into a map by file name and assume that the folder is laid out
% correctly.
chnFileInfo = dir([folderpath filesep '*.chn']);
if isempty(chnFileInfo)
  ex = MException('importDTSFolder:badPath', ...
    'Error: path "%s" is given as a top-level DTS data directory but no ".chn" files is found.',folderpath);
  throwAsCaller(ex);
end

for fileNo = 1:length(chnFileInfo)
  chnFilePath = [folderpath filesep chnFileInfo(fileNo).name];
  fileContents = readDTSCHNFile(chnFilePath);
  out.contents(chnFileInfo(fileNo).name) = fileContents;
end

end

function out = makeDTSMetaNode( )
% makeDTSMetaNode Return a DTS meta data structure. Useful for preallocation and
% easy reference.
%
%   The structure contains the following fields
%   - 'attributes' containing a containers.Map of key/value pairs. The keys are
%   the name of the XML attribute and the values are XML attribute values.
%   - 'value' containing the concatenated value of the XML node. Although valid
%   XML, if an XML node appears in the middle of the 'value' tag, it is not a
%   valid DTS meta XML file and generates an exception.
%   - 'children' containing a containers.Map of key/value pairs. The keys are
%   the name of the XML child tag and the values are a nested structures of this
%   structure model
  out = struct( ...
    'attributes',containers.Map('KeyType','char','ValueType','char'), ...
    'value',[], ...
    'children',containers.Map('KeyType','char','ValueType','any'));
end


function out = makeDTSCHNContents( )
% makeDTSCHNContents Return a DTS contents structure. Useful for preallocation
% and easy reference.
%
% The structure contains the following fields based on V4 of the DTS binary file
% format documentation.
out = struct( ...
  'versionNo',[], ...
  'numSamples',[], ...
  'bitsPerSample',[], ...
  'samplesSigned',[], ...
  'sampleRate',[], ...
  'numTriggers',[], ...
  'triggerSamples',[], ...
  'pretestZeroLevelinCounts',[], ...
  'removedADCLevelinCounts',[], ...
  'pretestDiagnosticsLevelinCounts',[], ...
  'pretestNoiseLevelinPercentageFS',[], ...
  'posttestZeroLevelinCounts',[], ...
  'posttestDiagnosticsLevelinCounts',[], ...
  'dataZeroLevelinCounts',[], ...
  'scaleFactormV',[], ...
  'scaleFactorEU',[], ...
  'EUFieldLength',[], ...
  'engineeringUnits',[], ...
  'excitation',[], ...
  'triggerAdjustmentSamples',[], ...
  'zeromVinCounts',[], ...
  'windowAverageinCounts',[], ...
  'originalOffsetinCounts',[], ...
  'ISOCode',[], ...
  'ADCCounts',[]);

end


function out = readDTSCHNFile( filepath )
%readDTSCHNFile Read a DTS .chn file and return the contents in a structure
%   The returned structure is defined in makeDTSCHNContents. N.B. fields that represent
%   internals to the parsing (bytestart) or file identification(magic number)
%   are not included in the returned struct.

out = makeDTSCHNContents();

% CHN files appear to be little endian but not documented anywhere
fid = fopen(filepath,'r','l');
if fid < 0
  ex = MException('DTSCHNReader:badFilePath', ...
    'Error: unable to open file path "%s"',filepath);
  throw(ex);
end

% Offset: 0
magicKey = fread(fid,1,'*uint32');
if magicKey ~= hex2dec('2C36351F')
  ex = MException('DTSCHNReader:badFilePath', ...
    'Error: file path "%s" does not point to a valid ".chn" file',filepath);
  throwAsCaller(ex);
end

% Offset: 4
% File version 4 is the only file version supported
out.versionNo = fread(fid,1,'*uint32');
if out.versionNo ~= 4
  ex = MException('DTSCHNReader:badFilePath', ...
    'Error: Reader only supports file version 4. File path "%s" points to a ".chn" file with version %i',filepath,versionNo);
  throwAsCaller(ex);
end

% Offset: 8
% File Version 4:
%   This value is at least 132 bytes assuming that there are zero triggers
%   and the EU is zero length. Not sure how realisitic this is but it appears to
%   be the lower bound for a theoretically valid file
byteStart = fread(fid,1,'*uint64');
if byteStart < 132
  ex = MException('DTSCHNReader:corruptOrUnsupportedFile', ...
    'Error: Corrupt or unsupported CHN file "%s". Header does not appear to be fully formed.',filepath,versionNo);
  throwAsCaller(ex);
end


% rewind file for checksumming
if fseek(fid,0,'bof') < 0
  ex = MException('DTSCHNReader:unexpectedFileError', ...
    'Unexpected file seek error in "%s"',filepath);
  throwAsCaller(ex);
end

% dont read the CRC
header = fread(fid,byteStart-4,'*uint8');

% Since MATLAB indexes arrays and vectors from 1, the offsets are adjusted from
% the DTS literature to reflect this.

% Offset: 16
offset = 16;
wordlen = 8;
out.numSamples = typecast(header(offset+1:offset+wordlen),'uint64');

% Offset: 24
offset = offset+wordlen;
wordlen = 4;
out.bitsPerSample = typecast(header(offset+1:offset+wordlen),'uint32');

% Offset: 28
offset = offset+wordlen;
wordlen = 4;
out.samplesSigned = typecast(header(offset+1:offset+wordlen),'uint32'); % 0 == NO
if ~(out.samplesSigned == 0 || out.samplesSigned == 1)
  ex = MException('DTSCHNReader:corruptOrUnsupportedFile', ...
    'Error: Corrupt or unsupported CHN file "%s". Unexpected signed or unsigned samples flag of %i',filepath,out.samplesSigned);
  throwAsCaller(ex);
end

% Offset: 32
offset = offset+wordlen;
wordlen = 8;
out.sampleRate = typecast(header(offset+1:offset+wordlen),'double');

% Offset: 40
offset = offset+wordlen;
wordlen = 2;
out.numTriggers = typecast(header(offset+1:offset+wordlen),'uint16');

% Offset: 42
offset = offset+wordlen;
wordlen = 8;
out.triggerSamples = typecast(header(offset+1:offset+(out.numTriggers*wordlen)),'uint64');


% Offset: N + 42
% Offset: 42
offset = offset+(out.numTriggers*wordlen); % previous wordlen
wordlen = 4;
out.pretestZeroLevelinCounts = typecast(header(offset+1:offset+wordlen),'int32');

% Offset: N + 46
offset = offset+wordlen;
wordlen = 4;
out.removedADCLevelinCounts = typecast(header(offset+1:offset+wordlen),'int32');

% Offset: N + 50
offset = offset+wordlen;
wordlen = 4;
out.pretestDiagnosticsLevelinCounts = typecast(header(offset+1:offset+wordlen),'int32');

% Offset: N + 54
offset = offset+wordlen;
wordlen = 8;
out.pretestNoiseLevelinPercentageFS = typecast(header(offset+1:offset+wordlen),'double');

% Offset: N + 62
offset = offset+wordlen;
wordlen = 4;
out.posttestZeroLevelinCounts = typecast(header(offset+1:offset+wordlen),'int32');

% Offset: N + 66
offset = offset+wordlen;
wordlen = 4;
out.posttestDiagnosticsLevelinCounts = typecast(header(offset+1:offset+wordlen),'int32');

% Offset: N + 70
offset = offset+wordlen;
wordlen = 4;
out.dataZeroLevelinCounts = typecast(header(offset+1:offset+wordlen),'int32');

% Offset: N + 74
offset = offset+wordlen;
wordlen = 8;
out.scaleFactormV = typecast(header(offset+1:offset+wordlen),'double');

% Offset: N + 82
offset = offset+wordlen;
wordlen = 8;
out.scaleFactorEU = typecast(header(offset+1:offset+wordlen),'double');

% Offset: N + 90
offset = offset+wordlen;
wordlen = 2;
out.EUFieldLength = typecast(header(offset+1:offset+wordlen),'uint16'); % plus terminator

% Offset: N + 92
offset = offset+wordlen;
wordlen = out.EUFieldLength-1; % Do not include the terminator
if any(header(offset+1:offset+wordlen) > 128)
  warning('Warning: in file "%s", detected non-ASCII values when parsing header engineerning units. Values may be truncated depending on host architecture.',file);
end
out.engineeringUnits = cast(header(offset+1:offset+wordlen)','char'); % does not include terminator

% Offset: N + 92 + X
offset = offset+wordlen;
wordlen = 8;
out.excitation = typecast(header(offset+1:offset+wordlen),'double');

% Offset: N + 100 + X
offset = offset+wordlen;
wordlen = 4;
out.triggerAdjustmentSamples = typecast(header(offset+1:offset+wordlen),'int32');

% Offset: N + 104 + X
offset = offset+wordlen;
wordlen = 4;
out.zeromVinCounts = typecast(header(offset+1:offset+wordlen),'int32');

% Offset: N + 108 + X
offset = offset+wordlen;
wordlen = 4;
out.windowAverageinCounts = typecast(header(offset+1:offset+wordlen),'int32');

% Offset: N + 112 + X
offset = offset+wordlen;
wordlen = 4;
out.originalOffsetinCounts = typecast(header(offset+1:offset+wordlen),'int32');

% Offset: N + 116 + X
offset = offset+wordlen;
wordlen = 16;
if any(header(offset+1:offset+wordlen) > 128)
  ex = MException('DTSCHNReader:corruptOrUnsupportedFile', ...
    'Error: Corrupt or unsupported CHN file "%s". Unexpected non-ASCII values in ISO code field',filepath);
  throwAsCaller(ex);
end
out.ISOCode = cast(header(offset+1:offset+wordlen)','char');

% Offset: N + 120 + X
% Based Q&A from DTS, the CRC32 field is not actually a CRC32 checksum, it is
% supposedly a CRC16-CCITT checksum with bottom two bytes zeroed but the given
% checksum does not appear to match this value. Issue a warning that the header
% is not verified and move on until additional resolution is obtained.
topCRC32 = dec2hex(fread(fid,1,'*uint16'));

crc16 = crc16_CCITT(header);
warning('In file: "%s", header verification is currently skipped due to unknown DTS checksum algorithm',filepath);
% if crc16 ~= topCRC32
%   ex = MException('DTSCHNReader:corruptOrUnsupportedFile', ...
%     'Error: Corrupt or unsupported CHN file "%s". Header read verification failed.',filepath);
%   throwAsCaller(ex);
% end


bottomCRC32 = fread(fid,1,'*uint16');
if bottomCRC32 ~= 0
  ex = MException('DTSCHNReader:corruptOrUnsupportedFile', ...
    'Error: Corrupt or unsupported CHN file "%s". Unknown secondary header checksum.',filepath);
  throwAsCaller(ex);
end


currentFileLoc = cast(ftell(fid),'uint64');
if currentFileLoc ~= byteStart
  ex = MException('DTSCHNReader:corruptedFile', ...
    'Error: CHN file "%s" is corrupted. Data section is expected to start at byte %i but is actually %i.', ...
    filepath,byteStart,currentFileLoc);
  throwAsCaller(ex);
end


% Read actual ADC counts. Appears to be signed but not documented. First build
% bit depth
if out.samplesSigned
  readBitDepth = sprintf('*bit%i',out.bitsPerSample);
else
  readBitDepth = sprintf('*ubit%i',out.bitsPerSample);
end

out.ADCCounts = fread(fid,out.numSamples,readBitDepth);

if mod(out.bitsPerSample,8) ~= 0
  ex = MException('DTSCHNReader:corruptedFile', ...
    'Error: CHN file "%s" has unsupported sample bit depth "%i". Sample depths need to be multiples of 8.', ...
    filepath,bitsPerSample);
  throwAsCaller(ex);
end


end




function out = readDTSFile( filepath )
%readDTSFile Read a '.dts' file and return an array of DTSMetaNodes representing
%the contents.
%   As of this writing, a '.dts' file consists of a concatinated list of XML
%   files that likely are a result of a serization of internal DataPro GUI
%   business logic data structures. By being a concatination of several XML
%   files into a single file, the resulting file is not valid XML and therefore
%   is not likely to be correctly read by the variety of available XML readers.
%   This function splits the concatinated XML files and reads them individually
%   preserving the UTF-16 encoding. The resulting contents are placed into a
%   'DTSMetaNode' tree, one for each XML file read.
%
%   'filepath' The path to the '.dts' file.

fid = fopen(filepath,'r');
if fid < 0
  ex = MException('DTSFileReader:badFilePath', ...
    'Error: unable to open file path "%s"',filepath);
  throw(ex);
end

bom = fread(fid,2,'char*1');
fclose(fid);

% default is UTF-8 even though currently files are not encoded this way
xml_search_str='<?xml';
% First parse the Byte Order Mark. Currently the DTS files are concatonated xml
% files encoded in UTF-16LE
if (bom(1) == hex2dec('FF')) && (bom(2) == hex2dec('FE'))
  % UTF-16LE
  xml_search_str=unicode2native('<?xml','UTF-16LE');
elseif (bom(1) == hex2dec('FE')) && (bom(2) == hex2dec('FF'))
  % UTF-16BE
  xml_search_str=unicode2native('<?xml','UTF-16BE');
else
  % UTF-8, don't use BOM (although we could)
  bom='';
end

fid = fopen(filepath,'r');
if fid < 0
  ex = MException('DTSFileReader:badFilePath', ...
    'Error: unable to open previously opened file path "%s"',filepath);
  throw(ex);
end

contents = fread(fid,'char*1')';

XMLHeaderLocs = strfind(contents,xml_search_str);

% preallocate meta structure
out = makeDTSMetaNode();
out(length(XMLHeaderLocs)).value = [];

for i=1:length(XMLHeaderLocs)-1
  %fprintf('reading header %i\n',i);
  out(i) = readDTSXML(contents(XMLHeaderLocs(i):XMLHeaderLocs(i+1)-1),bom);
end

%fprintf('reading header %i\n',length(XMLHeaderLocs));
	out(length(XMLHeaderLocs)) = readDTSXML(contents(XMLHeaderLocs(length(XMLHeaderLocs)):end),bom);
end

function [ out ] = readDTSXML( data, bom )
  % dump out a temporary file for reading since xmlread needs a filename
  temp_path = [tempname,'.xml'];
  fid = fopen(temp_path,'w');
  fwrite(fid,bom);
  fwrite(fid,data);
  fclose(fid);

  % try to read the xml file, make sure we delete the temporary file even if
  % we run into errors
  try
    DOMnode = xmlread(temp_path);
    out = buildDTSMetaNode(DOMnode);

  catch err
    delete(temp_path);
    rethrow(err);
  end

  delete(temp_path);
end


function [ out ] = buildDTSMetaNode( node )
  out = makeDTSMetaNode();
  
  %fprintf('Processing node %s\n',char(node.getNodeName));
  if node.hasAttributes
    theAttributes = node.getAttributes;
    numAttributes = theAttributes.getLength;
    for count = 1:numAttributes
      attrib = theAttributes.item(count-1);
      %fprintf('-> %s: %s\n',char(attrib.getName),char(attrib.getValue));
      out.attributes(char(attrib.getName)) = char(attrib.getValue);
    end
  end

  if node.hasChildNodes
    childNodes = node.getChildNodes;
    numChildNodes = childNodes.getLength;

    for idx = 0:numChildNodes-1
      theChild = childNodes.item(idx);
      key = char(theChild.getNodeName);

      %fprintf('\tProcessing node %s; got node %s as type: %i\n',...
      %  char(node.getNodeName),char(theChild.getNodeName),theChild.getNodeType);

      switch theChild.getNodeType
        % element node. The node name is the key to another DTSMetaNode. There
        % may be more than one element node with this name so build a cell array
        % for each. Descend.
        case 1
          prev = [];
          if isKey(out.children,key)
            prev = out.children(key);
          end

          out.children(key) = [prev buildDTSMetaNode(theChild)];

%         % attribute node. The node name is the key to a DTSMetaAttribute. Do not
%         % descend
%         case 2
%           if isKey(result.attributes,key)
%             warning('Duplicate DTS file xml attribute "%s" on element "%s"', ...
%               key,char(node.getNodeName));
%           end
%
%           result.attributes(char(theChild.getName)) = char(theChild.getValue);

        % text node. There can be many text nodes, most will likely be nothing
        % but whitespace. Trim the leading and trailing whitespace and
        % concatanate
        case 3
          text = strtrim(char(theChild.getNodeValue));
          if ~isempty(text)
            out.value = [out.value {text}];
          end

        otherwise
          warning('Unrecognized DTS file xml node "%s"',char(theChild(getNodeType)));
      end


    end
  end
end




function verifyDTSTopFileMeta( nodeList )
%verifyDTSTopFileMeta Summary of this function goes here
%   Detailed explanation goes here

% verify nodeList is 2 nodes long
if length(nodeList) ~= 2
  ex = MException('verifyDTSTopFileMeta:unexpectedXMLInput','Expected 2 XML documents in the top-level .dts file, received %i .',...
    length(nodeList));
  throwAsCaller(ex);
end

verifyTestXMLNode(nodeList(1));
verifyTestSetupXMLNode(nodeList(2));

end

function verifyTestXMLNode( node)
%verifyTestXMLNode As of this writing, there is one child; 'Test'

if length(node.children) ~= 1
  ex = MException('verifyDTSTopFileMeta:unexpectedXMLInput','Expected a single "Test" node in the first XML structure in the given .dts file');
  throwAsCaller(ex);
end

node.children('Test'); % Throws if missing
end

function verifyTestSetupXMLNode( node)
%verifyTestXMLNode As of this writing, there is one child; 'Test'

if length(node.children) ~= 1
  ex = MException('verifyDTSTopFileMeta:unexpectedXMLInput','Expected a single "TestSetup" node in the second XML structure in the given .dts file');
  throwAsCaller(ex);
end

node.children('TestSetup'); % Throws if missing
end





function [ crc ] = crc16_CCITT( data )
%CRC-16-CCITT
%The CRC calculation is based on following generator polynomial:
%G(x) = x16 + x12 + x5 + 1
%
%The register initial value of the implementation is: 0xFFFF
%
%used data = string -> 1 2 3 4 5 6 7 8 9
%
% Online calculator to check the script:
%http://www.lammertbies.nl/comm/info/crc-calculation.html
%
%Taken from
%http://cn.mathworks.com/matlabcentral/fileexchange/47682-crc-16-ccitt-m/content//CRC_16_CCITT.m
%under a BSD license

%crc look up table
Crc_ui16LookupTable=[0,4129,8258,12387,16516,20645,24774,28903,33032,37161,41290,45419,49548,...
    53677,57806,61935,4657,528,12915,8786,21173,17044,29431,25302,37689,33560,45947,41818,54205,...
    50076,62463,58334,9314,13379,1056,5121,25830,29895,17572,21637,42346,46411,34088,38153,58862,...
    62927,50604,54669,13907,9842,5649,1584,30423,26358,22165,18100,46939,42874,38681,34616,63455,...
    59390,55197,51132,18628,22757,26758,30887,2112,6241,10242,14371,51660,55789,59790,63919,35144,...
    39273,43274,47403,23285,19156,31415,27286,6769,2640,14899,10770,56317,52188,64447,60318,39801,...
    35672,47931,43802,27814,31879,19684,23749,11298,15363,3168,7233,60846,64911,52716,56781,44330,...
    48395,36200,40265,32407,28342,24277,20212,15891,11826,7761,3696,65439,61374,57309,53244,48923,...
    44858,40793,36728,37256,33193,45514,41451,53516,49453,61774,57711,4224,161,12482,8419,20484,...
    16421,28742,24679,33721,37784,41979,46042,49981,54044,58239,62302,689,4752,8947,13010,16949,...
    21012,25207,29270,46570,42443,38312,34185,62830,58703,54572,50445,13538,9411,5280,1153,29798,...
    25671,21540,17413,42971,47098,34713,38840,59231,63358,50973,55100,9939,14066,1681,5808,26199,...
    30326,17941,22068,55628,51565,63758,59695,39368,35305,47498,43435,22596,18533,30726,26663,6336,...
    2273,14466,10403,52093,56156,60223,64286,35833,39896,43963,48026,19061,23124,27191,31254,2801,6864,...
    10931,14994,64814,60687,56684,52557,48554,44427,40424,36297,31782,27655,23652,19525,15522,11395,...
    7392,3265,61215,65342,53085,57212,44955,49082,36825,40952,28183,32310,20053,24180,11923,16050,3793,7920];

ui16RetCRC16 = hex2dec('FFFF');
for I=1:length(data)
    ui8LookupTableIndex = bitxor(data(I),uint8(bitshift(ui16RetCRC16,-8)));
    ui16RetCRC16 = bitxor(Crc_ui16LookupTable(double(ui8LookupTableIndex)+1),mod(bitshift(ui16RetCRC16,8),65536));
end

crc=ui16RetCRC16;


end

