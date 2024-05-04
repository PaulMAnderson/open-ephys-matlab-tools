

% sessionPath = 'G:\Neuropixels Test\DM07_test3_l_s_contra_stim2023-11-30_16-02-15d';
sessionPath = 'G:\Neuropixels Test\DM07_test3_l_s_contra_stim2023-11-30_16-02-15d';
% load Session
session = Session(sessionPath);
% Recording Node
node = session.recordNodes{1};
% Recording
recording = node.recordings{1};

% Lets get the clock events; 
events = recording.ttlEvents.values;
data = recording.continuous.values;
eventChannels = recording.ttlEvents.keys();
streams = recording.continuous.keys;

%% Going to loop through each data set and generate timestamps that match 
  % the AP stream, will only have valid timepoints between the first and
  % last clock event

for j = 1:length(recording.continuous)

    stream = recording.continuous(streams{j});

    fS(j) = data{j}.metadata.sampleRate;
    cS = events{j}.sample_number(events{j}.state);    
    clockSamples{j} = cS;
    sN = data{j}.sampleNumbers;
    sampleNumbers{j} = sN;

    firstClock = cS(1);
    lastClock  = cS(end);
    globalTimestamps = nan(size(sN));
    startTime = 0;
    endTime = length(cS) * 0.1;
    firstStamp = find(sN == firstClock);
    lastStamp  = find(sN == lastClock);
    globalTimestamps(firstStamp:lastStamp) = ...
        linspace(startTime,endTime, lastStamp - firstStamp + 1);

    stream.globalTimestamps = globalTimestamps;
    recording.continuous(streams{j}) = stream;
end


%% Plot aligned data
data = recording.continuous.values;

sect = 12000001:13000000;

[fig, ax] = myFig;
% Normalise datr
d1 = double(data{1}.samples(5,sect));
d1 = d1 - median(d1);
d1 = d1 ./ max(d1);
% max1 = max(d1);
% min1 = min(d1);
% d1 = (d1 - max1)./max1;

d2 = double(data{2}.samples(5,sect));
d2 = d2 - median(d2);
d2 = d2 ./ max(d2) ;
% max2 = max(d2);
% min2 = min(d2);
% d2 = (d2 - max2)./max2;

plot(data{1}.globalTimestamps(sect),d1);
plot(data{2}.globalTimestamps(sect),d2);


%% 
% % keep = sr == max(sr);
% 
% events = events(keep);
% data   = data(keep);

%% Now sync clock events

% get on events
for j = 1:length(events)
    onIdx  = events{j}.state == true;
%     offIdx = events{j}.state == false;
    syncEvents{j} = events{j}.sample_number(onIdx);
end

% Plot single channel and sync points
f = myFig;
for chan = 1:length(data)
    ax(chan) = subplot(length(data),1,chan);
    hold(ax(chan),'on');
    plot(data{chan}.sampleNumbers,data{chan}.samples(1,:));
    medianData = double(median(data{chan}.samples(1,:)));
    scatter(syncEvents{chan},ones(size(syncEvents{chan})).*medianData,'r*');

end

    









