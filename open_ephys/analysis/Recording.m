% MIT License

% Copyright (c) 2021 Open Ephys

% Permission is hereby granted, free of charge, to any person obtaining a copy
% of this software and associated documentation files (the "Software"), to deal
% in the Software without restriction, including without limitation the rights
% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
% copies of the Software, and to permit persons to whom the Software is
% furnished to do so, subject to the following conditions:

% The above copyright notice and this permission notice shall be included in all
% copies or substantial portions of the Software.

% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
% SOFTWARE.

classdef (Abstract) Recording < handle

    %RECORDING - Abstract class representing data from a single Recording
    % RECORDING - Classes for different data formats should inherit from this class.
    %
    % Recording objects contain three properties:
    % - continuous
    % - ttlEvents
    % - spikes
    %
    % SYNTAX:
    %   recordNode = RecordNode( 'path/to/record/node' )
    %
    % PROPERTIES:
    %   directory - the root directory that contains the recorded continuous, events and spike data
    %   experimentIndex - the index of an experiment within a session
    %   recordingIndex - the index of a recording within an experiment 
    %
    %   continuous is a list of data streams
    %       - samples (memory-mapped array of dimensions samples x channels)
    %       - timestamps (array of length samples)
    %       - metadata (contains information about the data source)
    
    %   spikes is a list of spike sources
    %       - waveforms (spikes x channels x samples)
    %       - timestamps (one per spikes)
    %       - electrodes (index of electrode from which each spike originated)
    %       - metadata (contains information about each electrode)
    %
    %   ttlEvent data is stored in a n x 4 array containing four columns:
    %       - timestamp
    %       - channel
    %       - nodeId (processor ID)
    %       - state (1 or 0)

    properties

        format

        directory
        experimentIndex
        recordingIndex

        continuous
        ttlEvents
        spikes

        messages

        barcodes
        syncLines

        

    end

    methods

        function self = Recording(directory, experimentIndex, recordingIndex)
            
            self.directory = directory;
            self.experimentIndex = experimentIndex;
            self.recordingIndex = recordingIndex;

            self.continuous = containers.Map();
            self.ttlEvents = containers.Map();
            self.spikes = containers.Map();

            self.messages = containers.Map();

            self.barcodes  = {};
            self.syncLines = {};
            
        end

        function self = addSyncLine(self, line, processorId, streamIdx, streamName, isMain, isBarcode)

            % Specifies an event channel to use for timestamp synchronization. Each
            % sync channel in a recording should receive its input from the same
            % physical digital input line.

            % For synchronization to work, there must be one (and only one) main
            % sync channel, to which all timestamps will be aligned.

            % Parameters
            % ----------
            % line : int
            %     event channel number
            % processorId : int
            %     ID for the processor receiving sync events
            % streamName : string
            %     name of the stream the line belongs to
            %     default = 0
            % main : bool
            %     if True, this processors timestamps will be treated as the main clock

            if isMain
                %TODO: Check for existing main and either overwrite or show
                %warning
            end

            syncChannel = {};
            syncChannel.line = line;
            syncChannel.processorId = processorId;
            syncChannel.streamName = streamName;
            syncChannel.isMain = isMain;
            syncChannel.isBarcode = isBarcode;
            syncChannel.streamName = streamName;

            streams = self.continuous.keys();

            for i = 1:length(streams)
                stream = self.continuous(streams{i});
                if strcmp(stream.metadata.streamName, syncChannel.streamName)
                    syncChannel.sampleRate = stream.metadata.sampleRate;
                    Utils.log("Setting sync channel ", num2str(i), " to ", stream.metadata.streamName, " @ ", num2str(stream.metadata.sampleRate));
                end
            end

            for i = 1:length(self.syncLines)

                if self.syncLines{i}.processorId == processorId && strcmp(self.syncLines{i}.streamName, streamName)

                    Utils.log("Found existing sync line, overwriting with new line!");
                    self.syncLines{streamIdx} = syncChannel;
                    break;

                end

                if i == length(self.syncLines)
                    self.syncLines{end+1} = syncChannel;
                end

            end

            if isempty(self.syncLines)
                self.syncLines{end+1} = syncChannel;
            end

        end

        function self = computeGlobalTimestamps(self)
            % Modified to preferentially use barcode sync times if they
            % exist
            streams = self.continuous.keys;

            if ~isempty(self.barcodes) && length(self.barcodes) >= 2
                % Use barcodes to sync
                % Get Main line
                mainIdx = 0;
                for j = 1:length(self.barcodes)
                    try
                        if self.barcodes{j}.isMain
                            main = self.barcodes{j};
                            mainIdx = j;                    
                        end
                    end
                end
                if mainIdx < 1
                    Utils.log("No main line designated by user, assuming first available barcode is main...");
                    mainIdx = 1;
                    main = self.barcodes{mainIdx};
                end

                for j = 1:length(self.barcodes)
                    if j == mainIdx
                        stream = self.continuous(main.streamName);
                        stream.globalTimestamps = ...
                            double(stream.sampleNumbers - main.barcodes.startLatency(1)) ...
                            / main.sampleRate;
                        self.continuous(main.streamName) = stream;
                        continue
                    else
                        sync = self.barcodes{j};
                        % First check barcodes match
                        if ~isequal(main.barcodes.barcodeValue,...
                                    sync.barcodes.barcodeValue) || ...
                            height(main.barcodes) ~= height(sync.barcodes)
                            Utils.log("Barcode values don't match");
                            return
                        else
                            % Get the data
                            stream = self.continuous(sync.streamName);
                            % Get samples as doubles
                            sampleNumbers = double(self.continuous(sync.streamName).sampleNumbers);
                            % Interpolate betweeen these and the main line
                            % barcode sample times
                            interpolatedSamples = interp1(double(sync.barcodes.startLatency),...
                                double(main.barcodes.startLatency),double(sampleNumbers));      
                            % Set the first barcode sample point to be zero
                            % and convert to seconds
                            interpolatedTimestamps = (interpolatedSamples ...
                                                    - double(main.barcodes.startLatency(1))) ...
                                                    / sync.sampleRate;     
                            % Now we still have NaN values before and after
                            % the last timestamp we can estimate these
                            % values
                            stepSize = mode(diff(interpolatedTimestamps));
                            % First the values at the start
                            realStart = find(~isnan(interpolatedTimestamps),1);
                            realStartValue = interpolatedTimestamps(realStart);
                            nanEnd = realStart - 1;
                            interpolatedTimestamps(1:nanEnd) = ...
                                nanEnd*-stepSize:stepSize:-stepSize;
                            % Now the ending ones
                            nanStart = find(isnan(interpolatedTimestamps),1);
                            nanSteps = length(interpolatedTimestamps) - nanStart;
                            interpolatedTimestamps(nanStart:end) = ...
                                interpolatedTimestamps(nanStart-1)+stepSize:...
                                stepSize:interpolatedTimestamps(nanStart-1)...
                                 + stepSize + stepSize*nanSteps;
                            % Assign to structs
                            stream.globalTimestamps = interpolatedTimestamps;
                            self.continuous(sync.streamName) = stream;                                                

                        end
                    end


                end

            % After sync channels have been added, this function computes the
            % the global timestamps for all processors with a shared sync line

            elseif ~isempty(self.syncLines)
    
                % Identify main sync line
                mainIdx = 0;
                for i = 1:length(self.syncLines)
                    if self.syncLines{i}.isMain
                        main = self.syncLines{i};
                        mainIdx = i;
                        break;
                    end
                end


    
                if length(self.syncLines) < 2
                    Utils.log("Computing global timestamps requires at least two auxiliary sync channels!");
                    return;
                elseif mainIdx == 0
                    Utils.log("No main line designated by user, assuming first available sync is main...");
                    mainIdx = 1;
                    main = self.syncLines{mainIdx};
                end
    
                Utils.log("Found main stream: ", num2str(mainIdx));
    
                eventProcessors = self.ttlEvents.keys;
    
                % Get events for main sync line
                for i = 1:length(eventProcessors)
    
                    events = self.ttlEvents(eventProcessors{i});
                    % Subset to get only sync events
                    events = DataFrame(events(events.line == main.line,:));
    
                    if events.line(1) == main.line && ...
                            strcmp(eventProcessors{i}, main.streamName)
    
                        mainStartSample = events.sample_number(1);
                        mainTotalSamples = events.sample_number(end) - mainStartSample;
    
                    end
    
                end
    
                % Update sync parameters for main sync
                self.syncLines{mainIdx}.start = mainStartSample;
                self.syncLines{mainIdx}.scaling = 1;
                self.syncLines{mainIdx}.offset = mainStartSample;
    
                % Update sync parameters for auxiliary lines
                for i = 1:length(self.syncLines)
    
                    if ~(i == mainIdx)
    
                        for j = 1:length(eventProcessors)
    
                            events = self.ttlEvents(eventProcessors{j});
                            events = DataFrame(events(events.line == main.line,:));
    
                            if events.line(1) == self.syncLines{i}.line && ...
                                events.processor_id(1) == self.syncLines{i}.processorId && ...
                                events.stream_name(1) == self.syncLines{i}.streamName
    
                                auxStartSample = events.sample_number(1);
                                auxTotalSamples = events.sample_number(end) - auxStartSample;
                                self.syncLines{i}.start = auxStartSample;
                                self.syncLines{i}.scaling = double(mainTotalSamples) / double(auxTotalSamples);
                                self.syncLines{i}.offset = mainStartSample;
                                self.syncLines{i}.sampleRate = self.syncLines{mainIdx}.sampleRate;
    
                            end
    
                        end
    
                    end
    
                end
    
                % Compute global timestamps for all channels
                for i = 1:length(self.syncLines)
    
                    sync = self.syncLines{i};
    
                    streams = self.continuous.keys;
    
                    for j = 1:length(streams)
    
                        stream = self.continuous(streams{j});
    
                        if strcmp(stream.metadata.streamName, sync.streamName)
                            
                            % This is the standard way, means that
                            % timestamps start at onset of GUI data
                            % streaming (not even the recording)
%                             stream.globalTimestamps = (stream.sampleNumbers - sync.start) * sync.scaling + sync.offset;
                            % My way 0 is the first sync event
                             stream.globalTimestamps = (stream.sampleNumbers - sync.start) * sync.scaling;
    
                            if self.format ~= "NWB"
    
                                stream.globalTimestamps = double(stream.globalTimestamps) / sync.sampleRate;
    
                            end
    
                            self.continuous(streams{j}) = stream;
    
                        end
    
                    end
    
                end
            else
                Utils.log("Need to specify at least 2 barcodes or syncLines");
                return;
            end
        end

        function self = extractBarcodes(self, varargin)

            %% Parse inputs
            p = inputParser; % Create object of class 'inputParser'
            
            addRequired(p, 'barcodeLine',@isnumeric); % Channel to search for barcodes
            addRequired(p, 'streamName',@ischar); % Stream to process
            addParameter(p, 'isMain',false,@islogical); % Number of bits in barcode
            addParameter(p, 'nBits',32,@isnumeric); % Number of bits in barcode
            addParameter(p, 'interval',10000,@isnumeric); % Inter-barcode interval in ms
            addParameter(p, 'initDuration',10,@isnumeric); % Duration of initalisation pulses
            addParameter(p, 'pulseDuration',30,@isnumeric); % Duration of barcode pulses
            addParameter(p, 'tolerance',0.1,@isnumeric); % Proporation of variation to accept 0.1 = 10%
            
            % Check the input 
            if isempty(varargin)
                Utils.log("Need to specify at least one event line as the barcode line");
                return;
            end
            parse(p, varargin{:});

            barcodeLine   = p.Results.barcodeLine;
            streamName    = p.Results.streamName;
            isMain        = p.Results.isMain;
            nBits         = p.Results.nBits;
            interval      = p.Results.interval;
            initDuration  = p.Results.initDuration;
            pulseDuration = p.Results.pulseDuration;
            tolerance     = p.Results.tolerance;
            
            %% extract barcodes here
            streamNames = self.continuous.keys();
            streamIdx   = strcmp(streamNames,streamName);

            events = self.ttlEvents(streamName);           
            eventTable = getTable(events);
            sampleRate = self.info.events{streamIdx}.sample_rate;
            msDiv = sampleRate / 1000;

            %% Now process for barcodes
            eventTable = eventTable(eventTable.line == barcodeLine,:);
            % If event 1 is an off we can ignore it
            while eventTable.state(1) == false
                eventTable(1,:) = [];
            end

            % If the last event is an on we can ignore it
            while eventTable.state(end) == true
                eventTable(end,:) = [];
            end

            %% Loop through events and get durations
            count = 1;
            barcodeNum = 1;
            initCodes = 0;

            for eventI = 1:2:height(eventTable)-1
                if eventTable.state(eventI+1) == false
                    % Get basic timing infor
                    eventData(count).latency  = eventTable.sample_number(eventI);
                    eventData(count).time     = double(eventData(count).latency) / sampleRate;
                    eventData(count).duration = double(eventTable.sample_number(eventI+1) ...
                        - eventTable.sample_number(eventI)) ./ msDiv;
                    % Get period that line was low prior to this event
                    if count == 1
                        eventData(count).offTime = 0;
                    else
                        eventData(count).offTime = round( (eventData(count).time - ...
                            eventData(count-1).time) * 1000 - eventData(count-1).duration );
                    end

                    % Determine the type of pulse
                    barcodeTolerance = pulseDuration*tolerance;
                    remainder = abs(rem(eventData(count).duration,pulseDuration));
                    if abs(remainder) <= barcodeTolerance
                        remainder = abs(remainder);
                    elseif abs(remainder - pulseDuration) <= barcodeTolerance
                        remainder = abs(remainder - pulseDuration);
                    end
                    if eventData(count).duration >= initDuration - (initDuration*tolerance) && ...
                            eventData(count).duration <= initDuration + (initDuration*tolerance)
                        eventData(count).type = 'wrapper';
                        initCodes = initCodes + 1;
                    elseif abs(remainder) <= pulseDuration*tolerance
                        eventData(count).type = 'barcode';
                    else
                        eventData(count).type = 'unknown';
                    end
                    eventData(count).barcodeNum = barcodeNum;
                    if initCodes >= 2
                        barcodeNum = barcodeNum + 1;
                        initCodes = 0;
                    end

                    count = count+1;
                else % ignore this event?
                    % Probably need some error checking here
                    warning('Missing an off event for a barcode pulse! Proceed with caution....');
                end
            end


            %% Loop through each barcode
            for barcodeI = 1:max([eventData.barcodeNum])
                barcode = zeros(1,nBits);

                idx = find([eventData.barcodeNum] == barcodeI & ...
                    ~strcmp({eventData.type},'unknown'));
                if ~isempty(idx)           
                    barcodeEvents = eventData(idx);
    
                    startTime    = barcodeEvents(1).time;
                    startLatency = barcodeEvents(1).latency;
    
                    barcodeEvents(strcmp({barcodeEvents.type},'wrapper')) = [];
    
                    for seqI = 1:length(barcodeEvents)
    
                        if seqI == 1
                            % Determine how many 0 bits were at the start
                            initialStep =round( (barcodeEvents(1).offTime - initDuration) / pulseDuration );
                            barcodeStep = 1 + initialStep;
                        else
                            offLength = round( barcodeEvents(seqI).offTime / pulseDuration );
                            barcodeStep = barcodeStep + offLength;
                        end
    
                        highLength = round(barcodeEvents(seqI).duration / pulseDuration);
                        barcode(barcodeStep:barcodeStep+highLength-1) = 1;
                        barcodeStep = barcodeStep + highLength;
                    end
    
                    barcodeValue = 0;
                    for bit = 1:length(barcode)
                        barcodeValue = barcodeValue + ...
                            2^(bit-1) * barcode(bit);
                    end
    
                    barcodeData(barcodeI).startTime = startTime;
                    barcodeData(barcodeI).startLatency = startLatency;
                    barcodeData(barcodeI).barcodeValue = barcodeValue;
                    barcodeData(barcodeI).barcodeNum = barcodeI;
    
                end
    
                barcodeStruct.line        = barcodeLine;
                barcodeStruct.processorId = eventTable.processor_id(1);
                barcodeStruct.streamName  = eventTable.stream_name{1};
                barcodeStruct.isMain      = isMain;
                barcodeStruct.sampleRate  = self.continuous(streamName).metadata.sampleRate;
                barcodeStruct.barcodes    = struct2table(barcodeData);
                
                   
                self.barcodes{streamIdx} = barcodeStruct;
            end

        end
        
    end

    methods (Abstract)

        loadSpikes(self)

        loadEvents(self)

        loadContinuous(self)

        %toString(self)

    end

    methods(Abstract, Static)

        detectFormat(directory) 
        
        detectRecordings(directory) 

    end

end