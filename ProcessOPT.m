%%%
% OPT Reconstruction script
% Eirinn Mackay, Wilson lab October 2017
% Inspired by Amin Allalou (Yanik lab)
%%%
% downscalefactor = 2;
use_image_warping = false;
disp('--- OPT Reconstruction script ----------------');
disp('--- Eirinn Mackay, Wilson lab October 2017 ---');
addpath(genpath('OPT-InSitu-Toolbox/optreconstruction'));
addpath(genpath('OPT-InSitu-Toolbox/3rdparty/astra-1.5'));
try
    d = gpuDevice;
    gpuAvailable = d.SupportsDouble;
    disp('GPU available!');
catch
    gpuAvailable = false;
    disp('No Nvidia GPU detected.');
end
cancelled = 0;
[VideoNames,VideoPath,FilterIndex] = uigetfile('*.avi','Please select the AVI file to be reconstructed:','MultiSelect','on');
% if ~iscell(VideoNames) 
%     if VideoNames == 0
%         return
%     end
% end
batchmode=1;
if ischar(VideoNames)
    VideoNames = {VideoNames};
    batchmode=0;
end
for V=1:length(VideoNames) % start a major loop through videos
VideoName = VideoNames{V};
if cancelled == 1
    break
end
%%
disp('Reading input video...');
disp(VideoName);
h = waitbar(0.33,'Loading video...');
videodata = read(VideoReader([VideoPath,VideoName]));
close(h);
% background = imread('background2018-02-23T16_38_32.bmp');
background = imread('background2018-03-06T17_46_17.bmp');
% b = imread('background2018-02-23T16_38_32.bmp');
% subtract the background. This will invert the brightness too
videodata = (background - videodata);

% clip the video to what I think are the best start and stop frames for
% this machine
video = videodata(:,:,:,10:379);
numslices = size(video,1);
image_width = size(video,2);
numchannels = size(video,3);
numframes = size(video,4);
clear videodata
f = figure;
%% Find the capillary walls

% vid_data = squeeze(video(:,:,2,:)); % grab one channel for this bit
% [~, maxslice] = max(sum(vid_data(100:end-200,100:end-100,1),2)); % find a good slice for later presentation 



% Fit the capillary to a sine curve and find the vertical offset 
% sino = double(squeeze(vid_data(1,:,:)))';

% 
% cap_mid = mean(cap_peak_points,2);
% [fitted, offset] = fit_sine(cap_mid);
% 
% vertical_adjustment = mean(fitted) - image_width/2;
% offset = offset - vertical_adjustment;
% cap_width = nanmedian(diff(cap_peak_points,1,2));
% cap_ideal_walls = [fitted - cap_width/2, fitted+cap_width/2];
% fprintf('Sinogram offset is %0.2f pixels\n',vertical_adjustment);
% subplot(2,2,2);
% imagesc(sino);
% hold on
% plot(cap_peak_points,'--', 'LineWidth',2,'Color','red');
% plot(cap_mid,'--', 'LineWidth',3,'Color','red');
% plot(fitted, '-', 'LineWidth',1,'Color','green');
% % plot(cap_mid+offset, '-', 'LineWidth',1,'Color','yellow');
% plot(cap_ideal_walls, '-','LineWidth',1,'Color','green');
% title('Capillary walls with sine fitting');
% hold off
% % clear vid_data

%% average every row, per frame, to make a blended sinogram
subplot(2,2,1);
imagesc(video(:,:,2,1));
title('Frame 1');

scanzones = squeeze(mean(video(:,:,2,:),1));
subplot(2,2,2);
imagesc(scanzones');
title("Average sinogram");
% for each consecutive frame, find the lateral movement that minimizes the
% difference (least squares)
shift_by = stabilize_capillary(scanzones);
shift_by = cumsum(shift_by);
% shift_by = cumsum(shift_by_again);
% scanzones = scanzones_fixed_1pass; %% TEMP
scanzones_fixed = scanzones;
for framenum = 1:numframes
    scanzones_fixed(:,framenum) = imtranslate(scanzones(:,framenum),[0 shift_by(framenum)],'linear');
end
% crop the fixed sinogram so there's no zeros
nz=find(min(scanzones_fixed,[],2));
crop_left = min(nz);
crop_right= max(nz);
scanzones_fixed = scanzones_fixed(crop_left:crop_right,:);
%display the fixed sinogram so we can see that it makes sense
subplot(2,2,3);
imagesc(scanzones_fixed');
title('Stabilized sinogram');
%% Stabilize whole video

% nz=find(min(scanzones_fixed,[],2));
% scanzones_fixed = scanzones_fixed(min(nz):max(nz),:);
% shift_by_again = stabilize_capillary(scanzones_fixed);
% shift_by_again = cumsum(shift_by_again);
% %%
% scanzones_fixed_again = scanzones_fixed;
% for framenum = 1:numframes
%     scanzones_fixed_again(:,framenum) = imtranslate(scanzones_fixed(:,framenum),[0 shift_by_again(framenum)],'linear');
% end
% nz=find(min(scanzones_fixed_again,[],2));
% scanzones_fixed = scanzones_fixed(min(nz):max(nz),:);
% %%
% apply this lateral shift to every frame in the video
h=waitbar(0,'Stabilizing video...');
for framenum = 1:numframes-1
    video(:,:,:,framenum) = imtranslate(video(:,:,:,framenum),[shift_by(framenum) 0 0],'linear');
    waitbar(framenum/numframes,h);
end
%crop the video to the stabilized region
video = video(:,crop_left:crop_right,:,:);
close(h);
% offset the found capillary walls by the same amount
% cap_peak_points_fixed = cap_peak_points+shift_by;
% edges = round(nanmean(cap_peak_points_fixed));  
% these edges will be used to crop and centre the sinogram prior to reconstruction
%% Find walls
capillary_endpoints = find_hough_points(squeeze(video(:,:,2,:)));

% draw the found capillary walls
found_walls = capillary_endpoints(capillary_endpoints(:,3)==1,1:2);
subplot(2,2,1);
imagesc(video(:,:,2,1));
for i = 1:size(found_walls)
    vline = line(found_walls(i,:), [1 numslices]);
    set(vline,'color','r');
    set(vline,'LineStyle','--');
    set(vline,'LineWidth',3);
end
title('Found capillary walls');

%% find walls using the capillary endpoints as a guide
subplot(2,2,3);
maxslice=600;
sino = squeeze(video(maxslice,:,2,:));
cap_peak_points = find_walls(double(sino), capillary_endpoints);
imagesc(sino);
hold on;
plot(cap_peak_points,'color','r','LineStyle',':','LineWidth',3);
hold off
view([-90 -90])
% what're the wall positions? 
edges = round(nanmedian(cap_peak_points)); 
%%
% v_complement = imcomplement(video);
% myVideo = VideoWriter([VideoPath,VideoName(1:end-4),'_stabilised.mp4'],'MPEG-4');
% open(myVideo);
% writeVideo(myVideo,v_complement);
% close(myVideo);
%% Reconstruct a slice
ch = 2; %channel 2 is the green channel which has a mix of ISH and SYTOX
slicenum = maxslice; % this is the slice with the highest intensity
subplot(2,2,1);
imagesc(video(:,:,ch,1));
hline = refline(0,slicenum);
    set(hline,'color','r');
    set(hline,'LineStyle','--');
title(sprintf('Test slice (ch%d)', ch));
line([edges(1) edges(1)],[1 numslices], 'color','r');
line([edges(2) edges(2)],[1 numslices], 'color','r');

angles = linspace(0,2*pi, numframes);

sino = squeeze(video(slicenum,:,ch,:));
contract_borders_by = -20;
leftedge = edges(1)+contract_borders_by;
rightedge = edges(2)-contract_borders_by;
plotresults = true;
subplot(2,2,2);
extra_offset = findCOR(sino, angles, leftedge,rightedge,0,'GDER',plotresults,gpuAvailable);
fprintf('Optimised COR offset is %0.2f pixels\n',extra_offset);
% extra_offset=0;%-14;
% display this reconstruction
contract_borders_by = -20;
leftedge = edges(1)+contract_borders_by+extra_offset;
rightedge = edges(2)-contract_borders_by+extra_offset;
subplot(2,2,3);
fixed_sino = sino(leftedge:rightedge,:);
imagesc(fixed_sino');
title('Sinogram for reconstruction');
% adjust the edges again to remove the capillary. This will get used in the
% final reconstruction.
contract_borders_by = +40;
leftedge = edges(1)+contract_borders_by+extra_offset;
rightedge = edges(2)-contract_borders_by+extra_offset;

subplot(2,2,4);
downsamplefactor = 1;
small_sino = imresize(fixed_sino, 1/downsamplefactor);
small_angles = decimate(angles,downsamplefactor);
rec_slice = reconstruct_from_sino(small_sino', small_angles,gpuAvailable);
rec_slice(rec_slice<0)=0;
imagesc(rec_slice);
title('Reconstructed slice');
daspect([1 1 1]);



%%
%subplot(2,2,3);
% 
% fixed_sino = sino(edges(1)-50:edges(2)+50,:);
% 
% %downsample for speed
% downsamplefactor = 2;
% small_sino = imresize(fixed_sino, 1/downsamplefactor);
% small_angles = decimate(angles,downsamplefactor);
% tic;
% rec_slice = reconstruct_from_sino(small_sino', small_angles,gpuAvailable);
% elapsedTime = toc;
% image_variance = var(rec_slice(:));
% image_focus = fmeasure(rec_slice,'GDER');
% fprintf('Reconstruction complete after %0.2f seconds.\nImage focus is %0.5f.\n',elapsedTime, image_focus);
% rec_slice(rec_slice<0)=0;
% subplot(2,2,4);
% imagesc(rec_slice);
% title('Reconstructed slice');
% daspect([1 1 1]);
%% Reconstruct all slices if it looks good
clear Movie;
framenum=1;
chans = [2 1 3];
image_width = size(fixed_sino,1);
if batchmode==0
    button = questdlg('Proceed with full reconstruction?','Hey','Yes','No','Yes');
    cancelled=0;
    if isequal(button,'No')
        cancelled = 1;
    end
end
if cancelled==0 %okay let's do this
    delete(f);
    downsamplefactor = 1;
    display_subplots = false;
    vol_width = ceil(image_width/downsamplefactor);
    vol_height = ceil(numslices/downsamplefactor);
    reconTimer = tic;
    vol_width = rightedge-leftedge+1;
    views = zeros(vol_width, vol_width, 3, vol_height,'uint8'); % this will hold our data
    fishmask = zeros(vol_width, vol_width, vol_height,'logical');
    for ch = chans
        if cancelled == 1
            break
        end
        fprintf('Reconstructing channel %d\n', ch);
        max_projection = zeros(vol_width, vol_height, 'uint8');
        first_frame = video(:,:,ch,1); %purely for subplot illustration
        h = waitbar(0,'Processing...','CreateCancelBtn','cancelled = 1; delete(h)');
        f = figure('CloseRequestFcn','cancelled = 1; delete(f);');
        slice_time_elapsed = 0.4; % start with a reasonable number for time estimation
        for slicenum = 1:downsamplefactor:numslices
            % check for cancel button
            if cancelled == 1
                break
            end
            tic
            seconds_remaining = slice_time_elapsed*(numslices - slicenum)/downsamplefactor;
            hms = fix(mod(seconds_remaining, [0, 3600, 60]) ./ [3600, 60, 1]);
%             fprintf('Time remaining: %02d:%02d:%02d\n', hms);
%             waitbar(slicenum/numslices, h, sprintf('Processing slice %d',slicenum));
            waitbar(slicenum/numslices, h, sprintf('Time remaining: %02d:%02d:%02d', hms));
            sino = (squeeze(video(slicenum,:,ch,:)));
            fixed_sino = sino(leftedge:rightedge,:);
            small_sino = imresize(fixed_sino, 1/downsamplefactor);
            small_angles = decimate(angles,downsamplefactor);
            % actually do the reconstruction
            rec_slice = reconstruct_from_sino(small_sino', small_angles,gpuAvailable);
            rec_slice(rec_slice<0)=0;
            rec_slice = uint8(round(rec_slice*64));
            % filter it
            rec_slice = medfilt2(rec_slice);
            % add the reconstruction to the volume
            downsampled_slicenum = uint16((slicenum-1)/downsamplefactor+1);
            views(:,:,ch,downsampled_slicenum) = rec_slice;
            % if this is channel 3, find the fish outline
            if ch == 2
                this_fishmask = find_mask(rec_slice, 0.07);
                fishmask(:,:,downsampled_slicenum) = this_fishmask;
            end
            slice_projection = max(rec_slice,[],1);
            max_projection(:,downsampled_slicenum) = slice_projection;
            
            if display_subplots
                subplot(2,2,1);
                imagesc(first_frame);
                hline = refline(0,slicenum);
                set(hline,'color','r');
                set(hline,'LineStyle','--');
                title(sprintf('Ch %d slice %d',ch,slicenum));
                subplot(2,2,2);
                imagesc(small_sino')
                title('Sinogram');
                subplot(2,2,3)
                imagesc(rec_slice)
                daspect([1 1 1]);
                title('Reconstruction (top view)')
%                 if ch == 3
%                     % draw the bounding box
%                     max_mask = squeeze(max(fishmask,[],3));
%                     whole_region = regionprops(max_mask);
%                     if ~isempty(whole_region)
%                         wholeBB = whole_region.BoundingBox;
%                         hold on
%                         rectangle('Position',wholeBB, 'EdgeColor','green','LineStyle','--');
%                         hold off
%                     end
%                 end
                subplot(2,2,4)
                imagesc(max_projection');
                daspect([1 1 1]);
                title('Max intensity projection')
                Movie(framenum) = getframe(gcf);
                framenum=framenum+1;
            else
                subplot(1,2,1);
                imagesc(rec_slice);
                daspect([1 1 1]);
                title(sprintf('Processing slice %d of %d',slicenum,numslices));
                subplot(1,2,2);

                imagesc(max_projection');
                daspect([1 1 1]);
                title('Projection')
            end
                    
            slice_time_elapsed = toc;
        end

        delete(f);
        delete(h);
    end
    % all channels complete
    hms = fix(mod(toc(reconTimer), [0, 3600, 60]) ./ [3600, 60, 1]);
    disp(sprintf("Elapsed time: %02d:%02d:%02d", hms));
    if cancelled == true
        disp('Processing cancelled.')
    else
        disp('Saving cropped volume...');
        h=waitbar(1,'Saving cropped volume to file...');
        %whole_region = regionprops(fishmask);
        %wholeBB3D = whole_region.BoundingBox; 
        %BB = round(wholeBB3D);
%         rec = views(BB(2):BB(2)+BB(5)-1,BB(1):BB(1)+BB(4)-1,BB(3):BB(3)+BB(6)-1,:);
%         mask = fishmask(BB(2):BB(2)+BB(5)-1,BB(1):BB(1)+BB(4)-1,BB(3):BB(3)+BB(6)-1);
        % the above approach (finding the biggest object in the 3d mask)
        % didn't work that well. Instead let's just take a max through the
        % stack and find the biggest object there.
        max_mask_topdown = squeeze(max(fishmask,[],3));
        max_mask_props = regionprops(max_mask_topdown);
        [~,mask_biggest_idx] = max([max_mask_props.Area]);
        BB = round(max_mask_props(mask_biggest_idx).BoundingBox);
        rec = views(BB(2):BB(2)+BB(4)-1, BB(1):BB(1)+BB(3)-1, :, :);
        mask = fishmask(BB(2):BB(2)+BB(4)-1, BB(1):BB(1)+BB(3)-1, :);
        save([VideoPath,VideoName(1:end-4),'_recon.mat'],'rec', 'mask','-v7.3');
        % Save the output to a TIFF stack
        % permute it to get a side-view 
%         dat = permute(rec, [1 4 2 3]);
        % and then reshape it to interleave the
        % colour channels (for ImageJ)
%         dat = reshape(permute(rec, [3 1 4 2]), size(rec,3), size(rec,1), []);
        outputfilename = [VideoPath,VideoName(1:end-4),'_recon.tiff'];
        options.overwrite = true;
        options.color = true;
        options.message = false;
        saveastiff(rec, outputfilename, options);
        disp('Done.');
        delete(h);
        clear dat
    end
end
%% Hard mask parts of the volume that aren't in the top-down mask
max_mask_topdown = squeeze(max(mask,[],3));
rec_masked = rec;
for slicenum=1:numslices
    rec_masked(:,:,:,slicenum) = imoverlay(rec(:,:,:,slicenum),~max_mask_topdown,[0 0 0]);
end
%%
% m = squeeze(max(dat,[],1));
% for ch=1:3
%     subplot(1,4,ch);
%     imagesc(m(:,:,ch));
%     daspect([1 1 1]);
%     title(sprintf('Channel %d', ch));
% end
% subplot(1,4,4);
% imagesc(imcomplement(histeq(m)));
% daspect([1 1 1]);
% title('Merge');
%%
% myVideo = VideoWriter([VideoPath,VideoName(1:end-4),'_reconanimation.mp4'],'MPEG-4');
% myVideo.FrameRate=60;
% open(myVideo);
% writeVideo(myVideo,Movie(1:1024));
% close(myVideo);
end %% end the major loop through videos

%% Attempt a 3d scatter plot render
% [xx,yy,zz] = meshgrid(1:134,1:119,1:256);
% n = nonzeros(Ds(Ds>5));
% n = find(D>5);
% [xx,yy,zz] = ind2sub(size(D),n);
% scatter3(xx,yy,zz,1,'Marker','.','MarkerEdgeAlpha',0.01);
% axis vis3d
% daspect([1,1,1]);
%% Prepare a downsampled volume mask
% meanrec = mean(rec,4);
% % B = imresize3(meanrec,0.25);
% B = imresize3(rec(:,:,:,2),0.25);
% BW = B>(10);
% CC = bwconncomp(BW);
% numOfPixels = cellfun(@numel,CC.PixelIdxList);
% [unused,indexOfMax] = max(numOfPixels);
% biggest = zeros(size(B),'logical');
% biggest(CC.PixelIdxList{indexOfMax}) = 1;
% %%
% BW = B>3;
% imagesc(squeeze(BW(80,:,:)))