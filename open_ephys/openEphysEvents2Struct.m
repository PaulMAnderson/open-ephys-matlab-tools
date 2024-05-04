function events = openEphysEvents2Struct(eventTable)

% Make sure is not a dataframe
if strcmp(class(eventTable),'DataFrame');
    eventTable = eventTable.getTable;
end



%% Loop through events
lines = unique(eventTable.line);
count = 1;
events(1:height(eventTable)) = struct('line',[],'latency',[],...
                                      'timestamp',[],'duration',[]);
for lineI = 1:length(lines)

    cLine = lines(lineI);
    lineEvents = eventTable(eventTable.line == cLine,:);

    for rowI = 1:height(lineEvents)

        if lineEvents.state(rowI) ==  false
            continue
        else
            events(count).type = cLine;
            events(count).latency   = lineEvents.sample_number(rowI);
            events(count).timestamp = lineEvents.timestamp(rowI);
            % find duration
            nextRow = rowI + 1; 
            while nextRow <= height(lineEvents) && lineEvents.state(nextRow) ~= false
                nextRow = nextRow + 1;
            end

            if lineEvents.state(nextRow) == true && nextRow == height(lineEvents)
                events(count).duration = nan;
            else
                events(count).duration = (lineEvents.timestamp(nextRow) - ...
                                         lineEvents.timestamp(rowI)) * 1000; % in ms
            end
        end
        count = count + 1;
    end   
end

events(count:end) = [];
