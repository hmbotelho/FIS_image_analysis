// FIS Image Analysis Macro (batch analysis tool)
// v1.1
// ==================================
// 
// Required input data:
//   * Raw timelapse microscopy images of the FIS assay
//	 * The files being analyzed are defined by the regular expressions in line 49 (variable 'regexfiles').
//	 * This macro works seamlessly with images renamed with the 'htmrenamer' R package [https://github.com/hmbotelho/htmrenamer].
//
// Functionality:
//	 * Segments organoids and performs object tracking and object-level quality control.
//   * Computes total organoid area per image, in a timelapse performed on a multi-well plate.
//   * Exports segmentation masks (object labels image) and *.csv data tables
// 
// 
// Author: Hugo M Botelho, BioISI/FCUL, University of Lisbon
// hmbotelho@fc.ul.pt
// November 2020
//
// -------------------------------------

// Segmentation variables
#@ String(value="=================== Segmentation settings ===================", visibility=MESSAGE) msg1
#@ String (label="Background filter", choices={"No Filter (flat background)", "Minimum", "Median", "Mean"}) bg_filter
#@ Integer (label="Radius of filter (if selected, pixel units)", value=50) radius_filter
#@ Float (label="Offset after background correction", value=0.005) subtract_offset
#@ String (label="Thresholding method", choices={"Manual", "Huang", "Intermodes", "IsoData", "IJ_IsoData", "Li", "MaxEntropy", "Mean", "MinError", "Minimum", "Moments", "Otsu", "Percentile", "RenyiEntropy", "Shanbhag", "Triangle", "Yen"}) thresholding_method
#@ Float (label="Manual threshold value", value=0.050) threshold_value
#@ Boolean (label="Fill all holes?", value=false) fillholes
#@ Boolean (label="Remove salt and pepper noise?", value=true) clean
#@ Boolean (label="Declump organoids? (watershed)", value=false) declump

// Quality control variables
#@ String (value=" ", visibility=MESSAGE) msg2
#@ String (value="=================== Quality control ===================", visibility=MESSAGE) msg3
#@ Boolean (label="Exclude objects touching the image border?", value=false) edge_exclude
#@ Integer (label="Minimum organoid area (μm²)", value=500) size_min
#@ Integer (label="Maximum organoid area (μm²)", value=9999999) size_max
#@ Float (label="Minimum organoid circularity", value=0) circularity_min
#@ Float (label="Maximum organoid circularity", value=1) circularity_max
#@ String (value=" ", visibility=MESSAGE) msg4
#@ String (value="Exclude organoids based on measurements?", visibility=MESSAGE) msg5
#@ String (label="Measurement", choices={"None - Do not exclude", "Integrated density", "Mean gray value", "Median grayvalue", "Modal gray value", "Standard deviation grayvalues", "Minimum gray value", "Maximum gray value", "Perimeter", "Major ellipse axis", "Minor ellipse axis", "Circularity", "Ellipse aspect ratio", "Roundness", "Solidity", "Maximum caliper (Feret's diameter)", "Minimum caliper (Feret's diameter)", "Skewness", "Form Factor"}) QC_measurement_name
#@ Float (label="Minimum allowed value", value=-9999999) QC_measurement_min
#@ Float (label="Maximum allowed value", value=9999999) QC_measurement_max

// Microscopy variables
#@ String (value=" ", visibility=MESSAGE) msg6
#@ String (value="=================== Microscopy settings ===================", visibility=MESSAGE) msg7
#@ Float (label="Pixel width/height (μm)", value=4.991) pixelsize
#@ String (label="Regular expression matching all files being analyzed", value=".*--C00(?:\\.ome)??.tif$") regexfiles

// File locations
#@ String (value=" ", visibility=MESSAGE) msg8
#@ String (value="=================== Folder locations ===================", visibility=MESSAGE) msg9
#@ File (label="Raw FIS images", style="directory") sourcefolder
#@ File (label="Results", style="directory") targetfolder

// Load settings
#@ String (value=" ", visibility=MESSAGE) msg10
#@ String (value="=================== Load settings ===================", visibility=MESSAGE) msg11
#@ String (value="Folder location and regular expression will be loaded as specified above", visibility=MESSAGE) msg12
#@ Boolean (label="Load settings?", value=false) load_settings





// If requested, load settings file
if(load_settings){
	path_settings = File.openDialog("Select settings file");
	previous_settings = read_settings(path_settings);

	bg_filter           = previous_settings[0];
	radius_filter       = previous_settings[1];
	subtract_offset     = previous_settings[2];
	thresholding_method = previous_settings[3];
	threshold_value     = previous_settings[4];
	fillholes           = previous_settings[5];
	clean               = previous_settings[6];
	declump             = previous_settings[7];
	edge_exclude        = previous_settings[8];
	size_min            = previous_settings[9];
	size_max            = previous_settings[10];
	circularity_min     = previous_settings[11];
	circularity_max     = previous_settings[12];
	QC_measurement_name = previous_settings[13];
	QC_measurement_min  = previous_settings[14];
	QC_measurement_max  = previous_settings[15];
	pixelsize           = previous_settings[16];
}



fis_analysis(bg_filter, radius_filter, subtract_offset, thresholding_method, threshold_value, fillholes, clean, declump, edge_exclude, size_min, size_max, circularity_min, circularity_max, QC_measurement_name, QC_measurement_min, QC_measurement_max, pixelsize, regexfiles, sourcefolder, targetfolder);



// Segments FIS fluorescence images and measures per-object area
// Implements
// Output: count masks and csv files with object features
//
// bg_filter			character, filter the raw fluorescence image with this filter to estimate background. See above for valid possibilities
// radius_filter		numeric, the filter radius
// subtract_offset		numeric, subtract this value after subtracting the filtered image to the raw one
// thresholding_method	character, the thresholding method. See above for valid possibilities
// threshold_value		numeric, the manual threshold value. Ignored if the method is not 'Manual'.
// fillholes			logical, fill all holes after segmentation? This is independent from the 'conditional fill holes' algorithm, which is always applied
// clean				logical, remove salt and pepper noise from the segmented image?
// declump				logical, apply watershed after segmentation?
// edge_exclude			logical, exclude objects touching the image border?
// size_min				numerical, the minimal area of valid objects.
// size_max				numerical, the maximal area of valid objects.
// circularity_min		numerical, the minimal circularity of valid objects.
// circularity_max		numerical, the maximal circularity of valid objects.
// QC_measurement_name	character, an optional object feature which can be used to discard aberrant objects (quality control). See above for valid possibilities.
// QC_measurement_min	numerical, the minimal value of the quality control parameter of valid objects.
// QC_measurement_max	numerical, the maximal value of the quality control parameter of valid objects.
// pixelsize			numerical, the xy pixel size, in microns.
// regexfiles			character, a regular expression matching the raw image files.
// sourcefolder			character, the folder with raw fluorescence images. Images are searched for in all subfolders, recursively.
// targetfolder			character, the folder where outputs should be saved.
function fis_analysis(bg_filter, radius_filter, subtract_offset, thresholding_method, threshold_value, fillholes, clean, declump, edge_exclude, size_min, size_max, circularity_min, circularity_max, QC_measurement_name, QC_measurement_min, QC_measurement_max, pixelsize, regexfiles, sourcefolder, targetfolder){

	//===================================================================================================
	//   INITIALIZE VARIABLES AND WORKSPACE   ===========================================================
	//===================================================================================================
	
	setBatchMode(true);
	
	QCmeasurementNamesPretty   = newArray("None - Do not exclude", "Integrated density", "Mean gray value", "Median grayvalue", "Modal gray value", "Standard deviation grayvalues", "Minimum gray value", "Maximum gray value", "Perimeter", "Major ellipse axis", "Minor ellipse axis", "Circularity", "Ellipse aspect ratio", "Roundness", "Solidity", "Maximum caliper (Feret's diameter)", "Minimum caliper (Feret's diameter)", "Skewness", "Form Factor");
	QCmeasurementNamesHeadings = newArray("",                      "IntDen",             "Mean",            "Median",           "Mode",             "StdDev",                        "Min",                "Max",                "Perim.",    "Major",              "Minor",              "Circ.",       "AR",                   "Round",     "Solidity", "Feret",                              "MinFeret",                           "Skew",     "FormFactor");
	hindex = getArrayIndexes(QCmeasurementNamesPretty, QC_measurement_name);
	QC_measurement_heading = QCmeasurementNamesHeadings[hindex[0]];
	
	// Regular expressions: defines which metadata is extracted from file & folder names.
	regex_path1     = "^(?<pathBase>.*)[\\\\/](?<platePath>.*)[\\\\/](?<wellPath>.*)[\\\\/](?<posPath>.*)$";
	regex_file1     = "^(?<plateName>.*)[-][-](?<compound>.*)[-][-](?<concentration>.*)[-][-]W(?<wellNum>.*)[-][-]P(?<posNum>.*)[-][-]T(?<timeNum>....)(?<zNum>[-][-]Z...)?+[-][-]C(?<Channel>..)(?:\\.ome)??\\.tif$";
	regex_file2     = "^(?<imageBaseName>.*)[-][-].*[.].*$";
	
	// Set measurements
	activeMeasurements = "area mean standard modal min centroid perimeter fit shape feret's integrated median skewness redirect=None decimal=3";
	run("Set Measurements...", activeMeasurements);
	
	// Check folder name format
	sourcefolder = replace(sourcefolder, "\\\\", "/");
	targetfolder = replace(targetfolder, "\\\\", "/");
	if(!endsWith(sourcefolder, "/")) sourcefolder = sourcefolder + "/";
	if(!endsWith(targetfolder, "/")) targetfolder = targetfolder + "/";
	targetfolder = targetfolder + File.getName(sourcefolder) + "--ij/";
	makeDirRecursive(targetfolder);
	
	
	
	// Process variables
	if(fillholes){
		fill_YN = " Yes";
	} else{
		fill_YN = "No";
	}
	if(clean){
		clean_YN = "Yes";
	} else{
		clean_YN = "No";
	}
	if(declump){
		declump_YN = "Yes";
	} else{
		declump_YN = "No";
	}
	if(edge_exclude){
		edge_exclude_YN = "Yes";
	} else{
		edge_exclude_YN = "No";
	}
	
	if(edge_exclude){
		i_edge_exclude = " exclude";
	} else{
		i_edge_exclude = "";
	}
	if(fillholes){
		i_fill = " include";
	} else{
		i_fill = "";
	}
	
	
	
	
	// Save analysis settings
	getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
	year = leftPad(year, 4);
	month = leftPad(month+1, 2);
	dayOfMonth = leftPad(dayOfMonth, 2);
	hour = leftPad(hour, 2);
	minute = leftPad(minute, 2);
	second = leftPad(second, 2);
	log_fname = targetfolder + "settings_" + year + "-" + month + "-" + dayOfMonth + "_";
	log_fname = log_fname + hour + "-" + minute + ".log";
	filehandle = File.open(log_fname);
	print(filehandle, "=============================================================================");
	print(filehandle, "FIS image analysis");
	print(filehandle, "v1.1");
	print(filehandle, "=============================================================================");
	print(filehandle, "");
	print(filehandle, "Source folder (raw data): " + sourcefolder);
	print(filehandle, "Target folder: " + targetfolder);
	print(filehandle, "");
	print(filehandle, "Selected settings:");
	print(filehandle, "");
	print(filehandle, "Image analysis settings");
	print(filehandle, "_____________________________________________________________________________");
	print(filehandle, "Background filter: " + bg_filter);
	if(bg_filter != "No Filter (flat background)"){
		print(filehandle, "Filter radius: " + radius_filter + " pixels");
	}
	print(filehandle, "Image offset: " + subtract_offset);
	print(filehandle, "Thresholding method: " + thresholding_method);
	if(thresholding_method == "Manual"){
		print(filehandle, "Manual threshold value: " + threshold_value);
	}
	print(filehandle, "Fill all holes: " + fill_YN);
	print(filehandle, "Remove salt & pepper noise: " + clean_YN);
	print(filehandle, "Declump organoids (watershed): " + declump_YN);
	print(filehandle, "");
	print(filehandle, "Quality control settings");
	print(filehandle, "_____________________________________________________________________________");
	print(filehandle, "Exclude organoids touching the image border: " + edge_exclude_YN);
	print(filehandle, "Minimum allowed organoid size: " + size_min + " um²");
	print(filehandle, "Maximum allowed organoid size: " + size_max + " um²");
	print(filehandle, "Minimum allowed organoid circularity: " + circularity_min);
	print(filehandle, "Maximum allowed organoid circularity: " + circularity_max);
	print(filehandle, "Additional QC parameter: " + QC_measurement_name);
	if(QC_measurement_name != QCmeasurementNamesPretty[0]){
		print(filehandle, "Minimum allowed QC parameter value: " + QC_measurement_min);
		print(filehandle, "Maximum allowed QC parameter value: " + QC_measurement_max);
	}
	print(filehandle, "");
	print(filehandle, "Microscopy settings");
	print(filehandle, "_____________________________________________________________________________");
	print(filehandle, "Pixel width/height: " + pixelsize + " um");
	print(filehandle, "Regular expression matching image files: " + regexfiles);
	print(filehandle, "");
	print(filehandle, "");
	print(filehandle, dayOfMonth + "-" + month + "-" + year);
	print(filehandle, hour + ":" + minute + ":" + second);
	File.close(filehandle);
	
	
	
	// Close unnecessary windows
	run("Close All");
	closeWindow("Results");
	closeWindow("Image quantification data");
	print("\\Clear");
	
	
	
	// Get file names
	allfiles = listFiles(sourcefolder, regexfiles, targetfolder + "temp.txt");
	count_images = allfiles.length;


	
	// Get folder names
	allfolders = newArray(count_images);
	for(i=0; i <count_images; i++){
		allfolders[i] = File.getParent(allfiles[i]);
	}
	allfolders = unique(allfolders);
	
	
	
	
	
	
	
	
	
	
	//===================================================================================================
	//   IMAGE ANALYSIS   ===============================================================================
	//===================================================================================================
	
	
	// Cycle through each folder and perform image analysis
	ImageNumber = 0;
	for(dirnum=0; dirnum<allfolders.length; dirnum++){
	
		showProgress(ImageNumber / count_images);
	
		// Create results table
		close("Image quantification data");
		res = "[Image quantification data]";
		run("New... ", "name="+res+" type=Table");
		print(res,"\\Headings:ImageNumber\tObjectNumber\tMetadata_Channel\tMetadata_FileLocation\tMetadata_MaskLocation\tMetadata_compound\tMetadata_concentration\tMetadata_imageBaseName\tMetadata_pathBase\tMetadata_plateName\tMetadata_platePath\tMetadata_posNum\tMetadata_posPath\tMetadata_timeNum\tMetadata_wellNum\tMetadata_wellPath\tAreaShape_Center_X\tAreaShape_Center_Y\tMath_area_micronsq\tTrackObjects_Label");
	
	
		// Initialize arrays
		array_ImageNumber            = newArray();
		array_ObjectNumber           = newArray();
		array_Metadata_Channel       = newArray();
		array_Metadata_FileLocation  = newArray();
		array_Metadata_MaskLocation  = newArray();
		array_Metadata_compound      = newArray();
		array_Metadata_concentration = newArray();
		array_Metadata_imageBaseName = newArray();
		array_Metadata_pathBase      = newArray();
		array_Metadata_plateName     = newArray();
		array_Metadata_platePath     = newArray();
		array_Metadata_posNum        = newArray();
		array_Metadata_posPath       = newArray();
		array_Metadata_timeNum       = newArray();
		array_Metadata_wellNum       = newArray();
		array_Metadata_wellPath      = newArray();
		array_AreaShape_Center_X     = newArray();
		array_AreaShape_Center_Y     = newArray();
		array_Math_area_micronsq     = newArray();
		array_TrackObjects_Label     = newArray();
	
		// Keep track of the count masks images in this folder
		path_masks_array             = newArray();
	
	
		// Select valid images in this folder
		parentfolder = allfolders[dirnum] + "/";
		files_in_folder = getFileList(parentfolder);
		ok_images = filterArrayRegex(files_in_folder, regexfiles);
		ok_images = AppendPrefixArray (ok_images, parentfolder);
		ok_images = Array.sort(ok_images);
		
		
		// This is the time lapse image analysis
		for(imgnum=0; imgnum<ok_images.length; imgnum++){
	
			// Compute path for the image masks
			folder_tree_below_sourcefolder = File.getParent(ok_images[imgnum]);
			folder_tree_below_sourcefolder = replace(folder_tree_below_sourcefolder, "\\\\", "/");
			if(endsWith(folder_tree_below_sourcefolder, "/") == false){
				folder_tree_below_sourcefolder = folder_tree_below_sourcefolder + "/";
			}
			folder_tree_below_sourcefolder = replace(folder_tree_below_sourcefolder, sourcefolder, "");
			folder_output = targetfolder + folder_tree_below_sourcefolder;
			file_masks = File.getName(ok_images[imgnum]);
			file_masks = substring(file_masks, 0, lastIndexOf(file_masks, ".")) + "--masks.tif";
			path_masks = folder_output + file_masks;
			path_masks_array = Array.concat(path_masks_array, path_masks);
	
	
			
			// Open image
			open(ok_images[imgnum]);
			frame_name = getTitle();
			ImageNumber++;
			run("Properties...", "unit=um pixel_width=" + pixelsize + " pixel_height=" + pixelsize);
	
	
	
			// Extract metadata
			Metadata_FileLocation  = ok_images[imgnum];
			file                   = File.getName(Metadata_FileLocation);
			path                   = File.getParent(Metadata_FileLocation);
	        Metadata_pathBase      = replace(path, regex_path1, "${pathBase}");
			Metadata_platePath     = replace(path, regex_path1, "${platePath}");
			Metadata_wellPath      = replace(path, regex_path1, "${wellPath}");
			Metadata_posPath       = replace(path, regex_path1, "${posPath}");
			Metadata_plateName     = replace(file, regex_file1, "${plateName}");
			Metadata_compound      = replace(file, regex_file1, "${compound}");
			Metadata_concentration = replace(file, regex_file1, "${concentration}");
			Metadata_wellNum       = replace(file, regex_file1, "${wellNum}");
			Metadata_posNum        = replace(file, regex_file1, "${posNum}");
			Metadata_timeNum       = replace(file, regex_file1, "${timeNum}");
			Metadata_Channel       = replace(file, regex_file1, "${Channel}");
			Metadata_imageBaseName = replace(file, regex_file2, "${imageBaseName}");
	
			
			// Segment image
			segmentObjects(bg_filter, radius_filter, subtract_offset, thresholding_method, threshold_value, clean, declump, true);
	
	
	
			// Correlate the t and t-1 images.
			// This is to improve segmentation because the fluorescence signal is diluted out at late time points
			// A simple "fill holes" is not suitable: one has to discriminate between true holes (which must be filled) and gaps between objects (which must not)
			if(imgnum == 0){
			
				// Frame 1
	
			} else{
			
				// Frames 2 to end
			
				// Find holes in this frame
				selectWindow(frame_name);
				run("Duplicate...", "title=noHoles_" + frame_name);
				run("Fill Holes");
				imageCalculator("Difference", "noHoles_" + frame_name, frame_name);
				rename("holes_" + frame_name);
					
				// Fill holes which already existed
				imageCalculator("AND", "t-1","holes_" + frame_name);
				rename("fillHoles_" + frame_name);
				close("holes_" + frame_name);
				imageCalculator("OR", frame_name, "fillHoles_" + frame_name);
				close("fillHoles_" + frame_name);
			}
	
	
	
			// Set up measurements. Enable area and QC measurements
			bgCorrImg_title = "bgCorr_" + frame_name;					// QC measurements are performed on the background-corrected, non-thresholded image
			activeMeasurements_thisImage = replace(activeMeasurements, "redirect=None", "redirect=" + bgCorrImg_title);
			run("Set Measurements...", activeMeasurements_thisImage);
	
			// Measure organoid area
			run("Analyze Particles...", "size=" + size_min + "-" + size_max + " circularity=" + circularity_min + "-" + circularity_max + " show=[Count Masks] display" + i_edge_exclude + " clear" + i_fill);
	
			// Compute features not built in ImageJ
			for (r = 0; r < nResults; r++) {
				perimeter  = getResult("Perim.", r);
				area       = getResult("Area", r);
				FormFactor = formFactor(area, perimeter);
	
				setResult("FormFactor", r, FormFactor);
			}
			updateResults();
	
			
			close(bgCorrImg_title);
			selectWindow(frame_name);
	
	
			// Apply object-based QC to masks image
			selectWindow("Count Masks of " + frame_name);
			if(QC_measurement_name != QCmeasurementNamesPretty[0]){


				// Get the QC measurement value for each organoid
				for (i = 0; i < nResults; i++) {
					QC_value = getResult(QC_measurement_heading, i);

					// Hide objects which do not satisfy the QC criteria
					if(QC_value < QC_measurement_min || QC_value > QC_measurement_max){
						ReplacePixelValues(i+1, i+1, 0);
					}
				}
	
			}

	
			// Save masks image
			makeDirRecursive(folder_output);
			run("glasbey_inverted");
			saveAs("Tiff", path_masks);
			close();

	
			// Store results
			for(objnum=0; objnum<nResults; objnum++){
	
				if(QC_measurement_name == QCmeasurementNamesPretty[0]){
					// QC has not been set. Accept the organoid in the dataset
					store_data = true;
				} else{
					// QC has been set. Only organoids meeting the criteria established by the user will be accepted
					QC_value = getResult(QC_measurement_heading, objnum);
					if(QC_value >= QC_measurement_min && QC_value <= QC_measurement_max){
						store_data = true;
					} else{
						store_data = false;
					}
				}
	
				if(store_data){
					array_ImageNumber            = Array.concat(array_ImageNumber, ImageNumber);
					array_ObjectNumber           = Array.concat(array_ObjectNumber, objnum+1);
					array_Metadata_Channel       = Array.concat(array_Metadata_Channel, Metadata_Channel);
					array_Metadata_FileLocation  = Array.concat(array_Metadata_FileLocation, Metadata_FileLocation);
					array_Metadata_MaskLocation  = Array.concat(array_Metadata_MaskLocation, path_masks);
					array_Metadata_compound      = Array.concat(array_Metadata_compound, Metadata_compound);
					array_Metadata_concentration = Array.concat(array_Metadata_concentration, Metadata_concentration);
					array_Metadata_imageBaseName = Array.concat(array_Metadata_imageBaseName, Metadata_imageBaseName);
					array_Metadata_pathBase      = Array.concat(array_Metadata_pathBase, Metadata_pathBase);
					array_Metadata_plateName     = Array.concat(array_Metadata_plateName, Metadata_plateName);
					array_Metadata_platePath     = Array.concat(array_Metadata_platePath, Metadata_platePath);
					array_Metadata_posNum        = Array.concat(array_Metadata_posNum, Metadata_posNum);
					array_Metadata_posPath       = Array.concat(array_Metadata_posPath, Metadata_posPath);
					array_Metadata_timeNum       = Array.concat(array_Metadata_timeNum, Metadata_timeNum);
					array_Metadata_wellNum       = Array.concat(array_Metadata_wellNum, Metadata_wellNum);
					array_Metadata_wellPath      = Array.concat(array_Metadata_wellPath, Metadata_wellPath);
					array_AreaShape_Center_X     = Array.concat(array_AreaShape_Center_X, round(getResultString("X", objnum) / pixelsize));
					array_AreaShape_Center_Y     = Array.concat(array_AreaShape_Center_Y, round(getResultString("Y", objnum) / pixelsize));
					array_Math_area_micronsq     = Array.concat(array_Math_area_micronsq, getResultString("Area", objnum));
					array_TrackObjects_Label     = Array.concat(array_TrackObjects_Label, NaN);
				}
				
			}
			closeWindow("Results");
	
	
			// Rename image
			selectWindow(frame_name);
			rename("t-1");
	
		}
	
		// Close open images
		close("t-1");


		// Track objects
		trackOrganoidLabels(path_masks_array, folder_output, true);

	
		// Store track objects results
			// Load numerical data from object tracking
			temp_time = newArray();
			temp_labels_untracked = newArray();
			temp_labels_tracked = newArray();
			selectWindow("matrix_image");
			getDimensions(width, height, channels, slices, frames);
			for(y=0; y<height; y++){
				temp_time = Array.concat(temp_time, getValue(0, y));
				temp_labels_untracked = Array.concat(temp_labels_untracked, getValue(1, y));
				temp_labels_tracked = Array.concat(temp_labels_tracked, getValue(2, y));
			}
			close("matrix_image");
	
			// Annotate arrays
			for(i=0; i<lengthOf(array_ObjectNumber); i++){
				time = array_Metadata_timeNum[i];
				untracked = array_ObjectNumber[i];
				for(j=0; j<lengthOf(temp_time); j++){
					if(temp_time[j] == time && temp_labels_untracked[j] == untracked){
						array_TrackObjects_Label[i] = temp_labels_tracked[j];
					}
				}
				
			}
	
		
		// Populate results table
		for(i=0; i<lengthOf(array_ObjectNumber); i++){
			print(res, array_ImageNumber[i] + "\t" + array_ObjectNumber[i] + "\t" + array_Metadata_Channel[i] + "\t" + array_Metadata_FileLocation[i] + "\t" + array_Metadata_MaskLocation[i] + "\t" + array_Metadata_compound[i] + "\t" + array_Metadata_concentration[i] + "\t" + array_Metadata_imageBaseName[i] + "\t" + array_Metadata_pathBase[i] + "\t" + array_Metadata_plateName[i] + "\t" + array_Metadata_platePath[i] + "\t" + array_Metadata_posNum[i] + "\t" + array_Metadata_posPath[i] + "\t" + array_Metadata_timeNum[i] + "\t" + array_Metadata_wellNum[i] + "\t" + array_Metadata_wellPath[i] + "\t" + array_AreaShape_Center_X[i] + "\t" + array_AreaShape_Center_Y[i] + "\t" + array_Math_area_micronsq[i] + "\t" + array_TrackObjects_Label[i]);
		}
		
		
		// Save measurements for this folder
		selectWindow("Image quantification data");
		saveAs("Text", folder_output + "objects.csv");
		close("Image quantification data");
	}
	
	
	
	
	
	
	
	
	//===================================================================================================
	//   THE END   ======================================================================================
	//===================================================================================================
	run("Set Measurements...", activeMeasurements);
	print("\\Clear");
	closeWindow("Log");
	closeWindow("Results");
	closeWindow("Image quantification data");
	waitForUser("The end", "Finished analyzing:  " + sourcefolder + "\n\nAnalysis results were saved in:  " + targetfolder);
	
}
	
	
	
	
	

































































//===================================================================================================
//   HELPER FUNCTIONS   =============================================================================
//===================================================================================================

// Segment organoids fluorescence image with the parameters provided
// Output: binary image
//
// bg_filter			character, "No Filter (flat background)", "Minimum", "Median", "Mean"
// radius_filter		numeric, radius of the filter above
// subtract_offset		numeric, subtract this value to all pixels after subtracting the raw and filtered image
// thresholding_method	character, the global thresholding method
// threshold_value		numeric, the manual threshold value. Ignored if 'thresholding_method' is 'Manual'.
// clean				logical, remove salt & pepper noise?
// keepBgCorr			logical, keep background corrected image open after running the function?
function segmentObjects(bg_filter, radius_filter, subtract_offset, thresholding_method, threshold_value, clean, declump, keepBgCorr) {

	// Sanity check
	supported_thresholding_methods = newArray("Manual", "Huang", "Intermodes", "IsoData", "IJ_IsoData", "Li", "MaxEntropy", "Mean", "MinError", "Minimum", "Moments", "Otsu", "Percentile", "RenyiEntropy", "Shanbhag", "Triangle", "Yen");
	thresh_regex = "^" + thresholding_method + "$";
	if(countArrayMatches(supported_thresholding_methods, thresh_regex)  != 1){
		exit("Invalid thresholding method: '" + thresholding_method + "'");
	}
	
	
	// 	Determine whether to apply a background filter or not
	// If 'bg_filter' does not match a known filter, the background is processed as being flat.
	suppported_filters = newArray("Minimum", "Median", "Mean");
	dofilter = false;
	for(i=0; i<lengthOf(suppported_filters); i++){
		if(bg_filter == suppported_filters[i]){
			dofilter = true;
		}
	}

	// ========= Image segmentation below

	// Keep track of image names
	imgname = getTitle();
	imgname2 = "filtered_" + imgname;

	// 1. Initialize
	run("16-bit");

	// 2. Background subtraction
	if(dofilter){
		run("Duplicate...", " ");
		rename(imgname2);
		run(bg_filter + "...", "radius=" + radius_filter);
		imageCalculator("Subtract", imgname, imgname2);
		close(imgname2);
	}
	selectWindow(imgname);

	// 3. Rescale intensity to [0 ~ 1]
	run("32-bit");

	getRawStatistics(nPixels, mean, min, max); 
	range = max - min;
	run("Subtract...", "value=&min"); 
	run("Divide...", "value=&range"); 

	// 4. Subtract offset (and strech intensities to [0 ~ 1]
	run("Subtract...", "value=" + subtract_offset);
	run("Multiply...", "value=" + 1/(1-subtract_offset));

	if(keepBgCorr){
		// Preserve the background-corrected image before segmentation
		// This is required for per-object intensity measurements (e.g. analyze particles)
		run("Duplicate...", "title=[bgCorr_" + imgname + "]");
		selectWindow(imgname);
	}

	// 5. Threshold
	if(thresholding_method == "Manual"){
		setOption("BlackBackground", true);
		getRawStatistics(nPixels, mean, min, max);
		setThreshold(threshold_value, max);
	} else{
		setAutoThreshold(thresholding_method + " dark");
	}
	run("Make Binary");

	// 6. Remove salt & pepper noise
	if(clean){
		run("Options...", "iterations=1 count=8 black pad do=Erode");
	}

	// 7. Watershed
	if(declump){
		run("Watershed");
	}

}


// Adapter function: enables using the listFilesRecursively() function properly
// Output: array
//
// dir		character, folder path
// regex	character, regular expression matching the desired files
// tempfile	character, path to a text file where results are temporarily stored. File is deleted once the function completes.
function listFiles(dir, regex, tempfile) {

	// Initialize a text file to temporarily store all filenames
	f = File.open(tempfile);
	
	// Call file listing function
	listFilesRecursively(dir, regex, tempfile);

	// Convert temporary file into array
	filestring = File.openAsString(tempfile);
	rows=split(filestring, "\n");

	// Delete temporary file
	File.close(f);
	File.delete(tempfile);
	
	return rows;
}


// Returns an array with all files matching the regular expression.
// Needs a temporary text file
// Output: array
//
// dir		character, folder path
// regex	character, regular expression matching the desired files
// tempfile	character, path to a text file where results are temporarily stored. File is deleted once the function completes.
function listFilesRecursively(dir, regex, tempfile) {

	close("Log");

	list = getFileList(dir);
	list = AppendPrefixArray(list, dir+"/");
	
	for (i=0; i<list.length; i++) {

		if (endsWith(list[i], "/")){
			listFilesRecursively(list[i], regex, tempfile);
		}
			
		else{
			if(matches(list[i], regex)){
				print("logging " + list[i]);
				File.append(list[i], tempfile);
			}
		}
	}

	close("Log");

}


// Closes the specified window
// Output: none
//
// windowname	character, name of the window
function closeWindow(windowname){
	while(isOpen(windowname)){
		selectWindow(windowname);
		run("Close");
	}
}

// Creates a folder, recursively
// Output: none
//
// dir	character, path to the new folder
function makeDirRecursive(dir){
	folders = split(dir, "/");
	
	if(startsWith(dir, "/")){
		temp = "/";			// macOS
	} else{
		temp = "";			// Windows
	}
	
	for(i=0; i<lengthOf(folders); i++){
		temp = temp + folders[i] + "/";
		if(!File.exists(temp)){
			File.makeDirectory(temp);
		}
	}
}


// This function adds a prefix to all elements of an array
// Output: array
//
// array	array, the array to be processed
// prefix	character, the prefix
function AppendPrefixArray (array, prefix){
	for (k=0; k<lengthOf(array); k++){
		array[k] = prefix + array[k];
	}
	return array;
}


// Subsets an array according to a regular expression
// Output: array
//
// array	array, the array to be processed
// regex	character, the regular expression matching the desired array elements
function filterArrayRegex(array, regex){
	filteredarray = newArray(0);
	for(i=0; i<array.length; i++){
		if(matches(array[i], regex)){
			filteredarray = Array.concat(filteredarray,array[i]);
		}
	}
	return filteredarray;
}


// Eliminate duplicates from an array
// Output: array
//
// array	array, the array to be processed
function unique(array){

	output = newArray();
	
	for(i=0; i<array.length; i++){

		// Check if 'output' already contains this element
		inoutput = false;
		for(j=0; j<output.length; j++){
			if(array[i] == output[j]){
				inoutput = true;
			}
		}

		if(inoutput == false){
			output = Array.concat(output,array[i]);
		}
		
	}

	return output;
}


// Returns an array with the indexes of all items named 'itemname' within 'array'
// Returns NaN if there is no item named 'itemname'
// Output: array
//
// array	array, the array to be processed
// itemname	character, the items to be found
function getArrayIndexes(array, itemname){

	result = newArray();
	for (i = 0; i < lengthOf(array); i++) {
		if(array[i] == itemname){
			result = Array.concat(result,i);
		}
	}

	// Deal with the case where no itemname is found
	if(lengthOf(result) == 0){
		result = newArray(NaN);
	}
	
	return result;
}


// Count the number of array items matching a regular expression
// Output: numeric
//
// array	array
// regex	character, regular expression to be matched
function countArrayMatches(array, regex){
	result = 0;
	for (i = 0; i < lengthOf(array); i++) {
		if(matches(array[i], regex)){
			result++;
		}
	}
	return result;
}


// Add padding zeroes
// https://imagej.nih.gov/ij/macros/misc/Conference%20Macros/07_Functions.ijm
// Output: character
//
// n		numeric or character, the element to be processed
// width	numeric, the number of characters after padding
  function leftPad(n, width) {
	s =""+n;
	while (lengthOf(s)<width)
		s = "0"+s;
	return s;
}


// Replaces all pixel values in a range by a single value
// Analogous magic wand + color fill
// Output: image
//
// pixelValueMin	numeric, the minimum grayvalue in the original image
// pixelValueMax	numeric, the maximum grayvalue in the original image
// replaceValue		numeric, the value to overwrite grayvalues between pixelValueMin and pixelValueMax
function ReplacePixelValues(pixelValueMin, pixelValueMax, replaceValue){

	// Select pixels
	setThreshold(pixelValueMin, pixelValueMax);
	run("Create Selection");
	resetThreshold;
	
	// Fill pixels
	setColor(replaceValue);
	fill();
	
	// Reset selection
	run("Select None");
}


// Form Factor = 4*π*Area/Perimeter2
// Output: number
//
// area			numeric
// perimeter	numeric
function formFactor(area, perimeter){
	FF = 4*PI*area/pow(perimeter, 2);
	return(FF);
}


// Tracks objects from count masks from a FIS time lapse
// Output 1: relabeled masks
// Output 2: report table (as image)
// https://github.com/hmbotelho/ImageJ_tracker
//
// files		array, paths to the count masks image
// targetfolder	character, where to save relabeled image. Ignored if replace_raw = true
// replace_raw	logical, should the original count masks images be replaced?
function trackOrganoidLabels(files, targetfolder, replace_raw) { 

	// Initialize
	images_tracked = newArray();	// Image names after tracking
	Ttime = newArray();				// Time values
	ToriginalID = newArray();		// The original labels
	TtrackedID = newArray();		// Label after tracking
	ThistoryROI = newArray();		// The most common label at a ROI in all previous time points
	maxID = 0;						// Keep track of the labels which have already been assigned
	previous_batch_mode = is("Batch Mode");
	setBatchMode(true);
		
	// <<<<<< T=0 >>>>>>>>
	
		open(files[0]);
		img_before = getTitle();
		getDimensions(width, height, channels, slices, frames);
		available_labels = unique_labels();
		available_labels = Array.sort(available_labels);
		maxID = available_labels[lengthOf(available_labels)-1];


		// Create relabeled image
		img_tracked = File.getName(files[0]);
		img_tracked = addFileSuffix(img_tracked, "--tracked");
		images_tracked = Array.concat(images_tracked, img_tracked);

		newImage(img_tracked, "16-bit black", width, height, 1);
		setMinAndMax(0, 255);
		run("glasbey_inverted");
		for(i=0; i<lengthOf(available_labels); i++){
			selectlabel(available_labels[i], img_before);
			selectWindow(img_tracked);
			run("Restore Selection");
			run("Set...", "value=" + available_labels[i]);
			run("Select None");
		}
		close(img_before);

		// Save relabeled image
		selectWindow(img_tracked);
		if(replace_raw){
			//File.delete(files[0]);
			saveAs("Tiff", files[0]);
			rename(img_tracked);
		} else{
			saveAs("Tiff", targetfolder + "/" + img_tracked);
			rename(img_tracked);
		}

		// Make all background pixels NaN
		selectWindow(img_tracked);
		run("32-bit");
		changeValues(0, 0, NaN);
		run("glasbey_inverted");

		// Generate dataset
			
			// Time values
			Ttime = newArray(maxID);
			Array.fill(Ttime, 0);

			// The original labels
			ToriginalID = available_labels;
	
			// The final label assigned to the object
			TtrackedID = newArray(maxID);
			for(i=0; i<maxID; i++){
				TtrackedID[i] = i+1;
			}

			// The most common label in that position through time
			ThistoryROI = TtrackedID;


	
	// <<<<<< T>=1 >>>>>>>>

		for(t=1; t<lengthOf(files); t++){

			open(files[t]);
			img_before = getTitle();										// This is the image coming from 'Analyze Particles'
			available_labels = unique_labels();								// These are the labels contained in the image
			nID = lengthOf(available_labels);


			// Update dataset: time values
			temp_Ttime = newArray(nID);										// These are the values for this time point only
			Array.fill(temp_Ttime, t);
			Ttime = Array.concat(Ttime, temp_Ttime);


			// Update dataset: original labels
			temp_ToriginalID = available_labels;							// These are the values for this time point only
			ToriginalID = Array.concat(ToriginalID,temp_ToriginalID);


			// Update dataset: the most common label in that position through time
			temp_ThistoryROI = newArray();									// These are the values for this time point only
			for(i=0; i<lengthOf(available_labels); i++){

				selectlabel(available_labels[i], img_before);				// Establish ROI at the most recent time point
				past_IDs = newArray();
				past_IDs_flattened = newArray();
				
				for(t_past=0; t_past<lengthOf(images_tracked); t_past++){
					// Visit the same ROI in the past
					selectWindow(images_tracked[t_past]);
					run("Restore Selection");
					mode = round(getValue("Mode"));
					past_IDs = Array.concat(past_IDs,mode);
				}
				past_IDs_flattened = array_flatten(past_IDs);
				temp_ThistoryROI = Array.concat(temp_ThistoryROI,past_IDs_flattened);
			}
			ThistoryROI = Array.concat(ThistoryROI, temp_ThistoryROI);


			// Determine which label should be assigned to each project in the current time
			temp_TtrackedID = newArray();								// These are the values for this time point only
			for(i=0; i<lengthOf(temp_ThistoryROI); i++){
				new_label_raw = assign_label(temp_ThistoryROI[i], maxID);
				temp_TtrackedID = Array.concat(temp_TtrackedID, new_label_raw);
				
				// Check whether a new label has been assigned
				new_label_num = parseInt(new_label_raw);
				if(new_label_num > maxID){
					maxID = new_label_num;
				}
			}





			// Solve conflicts
			// This is required whenever multiple labels are allowed. e.g.: '3_4'
			// Algorithm:
			//	  - Disregard labels that have already been assigned to other objects in this image
			//    - If there are no labels left, assign a new label
			//    - Take all labels which have not been assigned in this image and select the lowest one
			labels_noconflicts = filterArrayRegex(temp_TtrackedID, "^[0-9]+$");
			for(i=0; i<lengthOf(temp_TtrackedID); i++){
				if(matches(temp_TtrackedID[i], ".*_.*")){
					
					// Process a conflict
					this_conflict_allpossibilities = split(temp_TtrackedID[i],"_");
					Array.sort(this_conflict_allpossibilities);
					this_conflict_allowedpossibilities = this_conflict_allpossibilities;

					for(j=0; j<lengthOf(labels_noconflicts); j++){
						this_conflict_allowedpossibilities = Array.deleteValue(this_conflict_allowedpossibilities, labels_noconflicts[j]);
					}

					if(lengthOf(this_conflict_allowedpossibilities) > 0){
						// There is at least one allowed possibility
						// Assign the lowest of the allowed possibilities
						temp_TtrackedID[i] = this_conflict_allowedpossibilities[0];
					} else{
						// None of the possibilities is allowed. Assign a new label
						maxID = maxID+1;
						temp_TtrackedID[i] = maxID;
					}
				}
			}



			
			TtrackedID = Array.concat(TtrackedID, temp_TtrackedID);
			
			


			// Create relabeled image
			img_tracked = File.getName(files[t]);
			img_tracked = addFileSuffix(img_tracked, "--tracked");
			images_tracked = Array.concat(images_tracked, img_tracked);
			newImage(img_tracked, "16-bit black", width, height, 1);
			setMinAndMax(0, 255);
			run("glasbey_inverted");
			for(i=0; i<lengthOf(temp_ToriginalID); i++){
				label_before = temp_ToriginalID[i];
				label_after = temp_TtrackedID[i];
				selectlabel(label_before, img_before);
				selectWindow(img_tracked);
				run("Restore Selection");
				run("Set...", "value=" + label_after);
				run("Select None");
			}
			close(img_before);
			
			// Save relabeled image
			selectWindow(img_tracked);
			if(replace_raw){
				//File.delete(files[t]);
				saveAs("Tiff", files[t]);
				rename(img_tracked);
			} else{
				saveAs("Tiff", targetfolder + "/" + img_tracked);
				rename(img_tracked);
			}

			// Keep tracked image open
			// Make all background pixels NaN
			selectWindow(img_tracked);
			run("32-bit");
			changeValues(0, 0, NaN);
			run("glasbey_inverted");
			
		}
		
		
	// Close open images
	for(i=0; i<lengthOf(images_tracked); i++){
		close(images_tracked[i]);
	}
	
	


	// Clean up
	setBatchMode(previous_batch_mode);

	
	
	
	// Return
	newImage("matrix_image", "16-bit black", 3, lengthOf(Ttime), 1);
	for(ii=0; ii<lengthOf(Ttime); ii++){
		setPixel(0, ii, Ttime[ii]);
	}
	for(ii=0; ii<lengthOf(ToriginalID); ii++){
		setPixel(1, ii, ToriginalID[ii]);
	}
	for(ii=0; ii<lengthOf(TtrackedID); ii++){
		setPixel(2, ii, TtrackedID[ii]);
	}
	
}


// Measure the modal value of a ROI in a set of images
// If there are more than one mode, select the lower value
// There must be an active ROI
// Output: array, the historial of modal values. The length is the number of images being analyzed
//
// filepaths	array, paths to the past images
function ROImode_paths(filepaths){

	result = newArray();
	
	// Check if there is a ROI
	if(Roi.size == 0){
		print("ROI not detected");
		for(i=0; i<lengthOf(filepaths); i++){
			result = Array.concat(result,NaN);
		}
		return result;
	}

	// Scan images
	for(i=0; i<lengthOf(filepaths); i++){
		open(filepaths[i]);
		imgname = getTitle();
		run("Restore Selection");
		result = Array.concat(result, getValue("Mode"));	// If there are multiple modes ImageJ selects the lowest value
		close(imgname);
	}

	return result;
}


// Measure the modal value of a ROI in a set of images
// If there are more than one mode, select the lower value
// Processes open images There must be an active ROI
// Output: array, the historial of modal values. The length is the number of images being analyzed
//
// imgnames		array, the names of images which should be analyzed
function ROImode_openimages(imgnames){

	main_img = getTitle();
	result = newArray();
	
	// Check if there is a ROI
	if(Roi.size == 0){
		print("ROI not detected");
		for(i=0; i<lengthOf(imgnames); i++){
			result = Array.concat(result,NaN);
		}
		return result;
	}

	// Scan images
	for(i=0; i<lengthOf(imgnames); i++){
		selectWindow(imgnames[i]);
		run("Restore Selection");
		result = Array.concat(result, getValue("Mode"));	// If there are multiple modes ImageJ selects the lowest value
		run("Select None");
	}
	selectWindow(main_img);
	
	return result;
}


// Select all pixels with a given label in  a given image
// Output: ROI
//
// label		numeric, the object label
// imagename	character, the name of the image to be analyzed
function selectlabel(label, imagename){
	selectWindow(imagename);
	setThreshold(label, label);
	run("Create Selection");
	run("glasbey_inverted");
}


// Converts the array '1, 2, 3, 4' into string '1_2_3_4'
// Output: character
//
// array	array
function array_flatten(array){

	if(lengthOf(array) == 1){
		return array;
	}
	
	result = "";
	for(i=0; i<lengthOf(array); i++){
		if(i<(lengthOf(array)-1)){
			result = result + array[i] + "_";
		} else{
			result = result + array[i];
		}
	}
	return result;
}


// Finds how many distinct labels there are in the open image
// Output: numeric
function count_labels(){

	// Check if there is an open image
	if (nImages == 0) {
		return(0);
	}

	// Initialize
	batch_mode = is("Batch Mode");
	setBatchMode(true);
	img_raw = getTitle();
	img_points_binary = "points--" + img_raw;
	img_points_labels = "labels--" + img_raw;
	count = 0;

	// Shrink eack object to a single pixel
	run("Duplicate...", "title=" + img_points_binary);
	setThreshold(1, 65535);
	run("Convert to Mask");
	run("Ultimate Points");
	setThreshold(1, 3255);
	run("Convert to Mask");
	run("Divide...", "value=255");
	imageCalculator("Multiply create", img_raw, img_points_binary);
	rename(img_points_labels);
	close(img_points_binary);
	selectWindow(img_points_labels);

	// Count 
	max_label = getValue("Max");
	for(label=1; label <= max_label; label++){
		setThreshold(label, label);
		run("Create Selection");
		mode = getValue("Mode");
		if(mode > 0){
			count++;
		}
	}
	close(img_points_labels);
	selectWindow(img_raw);
	setBatchMode(batch_mode);

	return count;
}


// Finds how many distinct labels there are in the open image
// Output: numeric
function unique_labels(){

	result = newArray();

	// Check if there is an open image
	if (nImages == 0) {
		return result;
	}

	// Initialize
	batch_mode = is("Batch Mode");
	setBatchMode(true);
	img_raw = getTitle();
	img_points_binary = "points--" + img_raw;
	img_points_labels = "labels--" + img_raw;
	result = newArray();

	// Shrink eack object to a single pixel
	run("Duplicate...", "title=" + img_points_binary);
	setThreshold(1, 65535);
	run("Convert to Mask");
	run("Ultimate Points");
	setThreshold(1, 3255);
	run("Convert to Mask");
	run("Divide...", "value=255");
	imageCalculator("Multiply create", img_raw, img_points_binary);
	rename(img_points_labels);
	close(img_points_binary);
	selectWindow(img_points_labels);

	// Count 
	max_label = getValue("Max");
	for(label=1; label <= max_label; label++){
		setThreshold(label, label);
		run("Create Selection");
		mode = getValue("Mode");
		if(mode > 0){
			result = Array.concat(result,label);
		}
	}
	close(img_points_labels);
	selectWindow(img_raw);
	setBatchMode(batch_mode);

	return result;
}


// Adds a suffix to a file name
// Converts 'filename.xxx' into 'filenamesuffix.xxx'
// Output: character
//
// filename		character, file name
// suffix		character, the suffix
function addFileSuffix(filename, suffix){
	regex = "^(?<pathBase>.*)\\.(?<extension>.*)$";
	result = replace(filename, regex, "${pathBase}" + suffix + ".${extension}");
	
	return result;
}


// Interprets a sequence of labels and returns the label which should be assigned in the current time point
// The labels are the modes in that ROI in all previous time points
// 'max_label' is the highest label previously assigned
// Output: character, the label to be assigned (or a set of acceptable labels)
//
// char			character, the historical sequence of labels
// max_label	numeric, the highest label ever assigned
function assign_label(char, max_label){
	history = split(char, "_");

	// No previous labels (i.e. all previous labels are NaN)
	// NaN_NaN_NaN_NaN
	// Assign a new label
	if(array_count(history, NaN) == lengthOf(history)){
		return max_label+1;
	}


	// Same label throughout
	// 4_4_4_4_4
	// Assign same label
	temp = unique(history);
	if(lengthOf(temp) == 1){
		return temp[0];
	}


	// Appears somewhere in the middle of the time lapse
	// NaN_NaN_NaN_7
	// NaN_7_7
	// Assign the same label
	regexNaN = "^(NaN_)+(\\d).*$";			// Match the initial NaNs
	regexNum = "^.*_(?<number>[0-9]+)$";		// Match any numbers. Important: will match 'NaN_7_7' but also 'NaN_7_8'!
	IDs = unique(history);
	if(matches(char, regexNaN) && matches(char, regexNum) && lengthOf(IDs) == 2){
		number = replace(char, regexNum, "${number}");
		number = parseInt(number);
		return number;
	}
		

	// Re-appearance of a previous object
	// NaN_NaN_7_NaN
	// Assign the last known label
	regexNaN = ".*NaN.*";					// Matches NaN
	regexNum = "(?<number>[0-9]++)";		// Matches '_(7)_'
	IDs = unique(history);
	if(matches(char, regexNaN) && lengthOf(IDs) == 2){
		if(IDs[0] == "NaN"){
			result = IDs[1];
		}else{
			result = IDs[1];
		}
		return parseInt(result);
	}
	

	// Variable label
	// NaN_NaN_7_NaN_4_NaN
	// Return a string with possible labels
	past_labels = newArray();
	for(i=0; i<lengthOf(history); i++){
		if(history[i] != "NaN"){
			past_labels = Array.concat(past_labels, history[i]);
		}
	}
	past_labels = unique(past_labels);
	Array.sort(past_labels);

	if(lengthOf(past_labels) > 1){
		result = array_flatten(past_labels);
		return result;
	}
	

	// Otherwise, assign a new label
	return max_label+1;
}


// Counts how many times 'item' shows up in 'array'
// Output: count
//
// array	array
// item		numeric or character, the item to be found
function array_count(array, item){
	result = 0;
	item = toString(item);
	
	for(i=0; i<lengthOf(array); i++){
		this_item = array[i];
		this_item = toString(this_item);
		if(item == this_item){
			result++;
		}
	}

	return result;
}


// Determines whether a string can be converted to an integer
// Output: true/false
//
// char		character
function isInteger(char){
	int = parseInt(char);
	float = parseFloat(char);
	
	if(isNaN(int) || isNaN(float)){
		return false;
	}
	
	decimal = float - int;
	if(decimal == 0){
		return true;
	}
	
	return false;
}


// Reads settings
// Output: array
//
// path		character, path to text file
function read_settings(path){

	varnames = newArray("bg_filter", "radius_filter", "subtract_offset", "thresholding_method", "threshold_value", "fillholes", "clean", "declump", "edge_exclude", "size_min", "size_max", "circularity_min", "circularity_max", "QC_measurement_name", "QC_measurement_min", "QC_measurement_max", "pixelsize");

	// Open file
	settings_txt = File.openAsString(path);
	settings_array = split(settings_txt, "\n");

	// Check version
	// This function requires version 1.1 or above
	version_txt = settings_array[2];
	regex_version = "^v(?<versionMajor>\\d+)\\.(?<versionMinor>\\d+)(\\.(?<versionRevision>\\d+))*?$";
	version_major = replace(version_txt, regex_version, "${versionMajor}");
	version_minor = replace(version_txt, regex_version, "${versionMinor}");
	version_revision = replace(version_txt, regex_version, "${versionRevision}");
	if(version_major < 1){
		exit("The load settings feature requires version 1.1 of the FIS analysis tool.");
	} else{
		if(version_minor < 1){
			exit("The load settings feature requires version 1.1 of the FIS analysis tool.");
		}
	}

	// Initialize variables
	result = newArray(17);
	Array.fill(result, NaN);
	regex_bg_filter           = "^Background filter: (?<setting>.*)$";
	regex_radius_filter       = "^Filter radius: (?<setting>.*)$";
	regex_subtract_offset     = "^Image offset: (?<setting>.*)$";
	regex_thresholding_method = "^Thresholding method: (?<setting>.*)$";
	regex_threshold_value     = "^Threshold value: (?<setting>.*)$";
	regex_fillholes           = "^Fill all holes: (?<setting>.*)$";
	regex_clean               = "^Remove salt&pepper noise: (?<setting>.*)$";
	regex_declump             = "^Declump organoids: (?<setting>.*)$";
	regex_edge_exclude        = "^Exclude organoids touching the image border: (?<setting>.*)$";
	regex_size_min            = "^Minimum allowed organoid size: (?<setting>.*) ...$";
	regex_size_max            = "^Maximum allowed organoid size: (?<setting>.*)...$";
	regex_circularity_min     = "^Minimum allowed organoid circularity: (?<setting>.*)$";
	regex_circularity_max     = "^Maximum allowed organoid circularity: (?<setting>.*)$";
	regex_QC_measurement_name = "^\\[QC\\] Further exclude organoids based on the following measurement: (?<setting>.*)$";
	regex_QC_measurement_min  = "^\\[QC\\] Minimum allowed measurement value: (?<setting>.*)$";
	regex_QC_measurement_max  = "^\\[QC\\] Maximum allowed measurement value: (?<setting>.*)$";
	regex_pixelsize           = "^Pixel width/height: (?<setting>.*) ..$";

	// Populate results array
	// Sanity checks
	for(i=0; i<lengthOf(settings_array); i++){
		line = settings_array[i];

		// bg_filter
		if(matches(line, regex_bg_filter)){
			bg_filter = replace(line, regex_bg_filter, "${setting}");
			allowed_filters = newArray("No Filter (flat background)", "Minimum", "Median", "Mean");
			if(array_count(allowed_filters, bg_filter) != 1) exit("Error loading settings file: unexpected 'bg_filter'.");
			
			result[0] = bg_filter;
		}


		// radius_filter
		if(matches(line, regex_radius_filter)){
			radius_filter = replace(line, regex_radius_filter, "${setting}");
			temp = parseFloat(radius_filter);
			if(isNaN(temp))  exit("Error loading settings file: unexpected 'radius_filter'.");
			if(temp < 0) exit("Cannot load settings: negative filter radius.");
		
			result[1] = radius_filter;
		}
		

		// subtract_offset
		if(matches(line, regex_subtract_offset)){
			subtract_offset = replace(line, regex_subtract_offset, "${setting}");
			temp = parseFloat(subtract_offset);
			if(isNaN(temp)) exit("Error loading settings file: unexpected 'subtract_offset'.");
			
			result[2] = subtract_offset;
		}


		// thresholding_method
		if(matches(line, regex_thresholding_method)){
			thresholding_method = replace(line, regex_thresholding_method, "${setting}");
			allowed_methods = newArray("Manual", "Huang", "Intermodes", "IsoData", "IJ_IsoData", "Li", "MaxEntropy", "Mean", "MinError", "Minimum", "Moments", "Otsu", "Percentile", "RenyiEntropy", "Shanbhag", "Triangle", "Yen");
			if(array_count(allowed_methods, thresholding_method) != 1) exit("Error loading settings file: unexpected 'thresholding_method'.");
			
			result[3] = thresholding_method;
		}


		// threshold_value
		if(matches(line, regex_threshold_value)){
			threshold_value = replace(line, regex_threshold_value, "${setting}");
			temp = parseFloat(threshold_value);
			if(isNaN(temp))  exit("Error loading settings file: unexpected 'threshold_value'.");
		
			result[4] = threshold_value;
		}


		// fillholes
		if(matches(line, regex_fillholes)){
			temp = replace(line, regex_fillholes, "${setting}");
			if(temp == "Yes") fillholes = true;
			if(temp == "No") fillholes = false;
			if(temp != "Yes" && temp != "No") exit("Error loading settings file: unexpected 'fillholes'.");
			
			result[5] = fillholes;
		}


		// clean
		if(matches(line, regex_clean)){
			temp = replace(line, regex_clean, "${setting}");
			if(temp == "Yes") clean = true;
			if(temp == "No") clean = false;
			if(temp != "Yes" && temp != "No") exit("Error loading settings file: unexpected 'clean'.");
			
			result[6] = clean;
		}

		
		// declump
		if(matches(line, regex_declump)){
			temp = replace(line, regex_declump, "${setting}");
			if(temp == "Yes") declump = true;
			if(temp == "No") declump = false;
			if(temp != "Yes" && temp != "No") exit("Error loading settings file: unexpected 'declump'.");
			
			result[7] = declump;
		}
		

		// edge_exclude
		if(matches(line, regex_edge_exclude)){
			temp = replace(line, regex_edge_exclude, "${setting}");
			if(temp == "Yes") edge_exclude = true;
			if(temp == "No") edge_exclude = false;
			if(temp != "Yes" && temp != "No") exit("Error loading settings file: unexpected 'edge_exclude'.");
			
			result[8] = edge_exclude;
		}


		// size_min
		if(matches(line, regex_size_min)){
			size_min = replace(line, regex_size_min, "${setting}");
			temp = parseFloat(size_min);
			if(isNaN(temp))  exit("Error loading settings file: unexpected 'size_min'.");
			if(temp < 0) exit("Cannot load settings: negative minimum size.");
			
			result[9] = size_min;
		}


		// size_max
		if(matches(line, regex_size_max)){
			size_max = replace(line, regex_size_max, "${setting}");
			temp = parseFloat(size_max);
			if(isNaN(temp))  exit("Error loading settings file: unexpected 'size_max'.");
			temp_min = parseFloat(size_min);
			temp_max = parseFloat(size_max);		
			if(temp_max < temp_min) exit("Size maximum is lower than size minimum");
			
			result[10] = size_max;
		}


		// circularity_min
		if(matches(line, regex_circularity_min)){
			circularity_min = replace(line, regex_circularity_min, "${setting}");
			temp = parseFloat(circularity_min);
			if(isNaN(temp))  exit("Error loading settings file: unexpected 'circularity_min'.");
			if(temp < 0) exit("Cannot load settings: negative circularity.");
			
			result[11] = circularity_min;
		}


		// circularity_max
		if(matches(line, regex_circularity_max)){
			circularity_max = replace(line, regex_circularity_max, "${setting}");
			temp = parseFloat(circularity_max);
			if(isNaN(temp))  exit("Error loading settings file: unexpected 'circularity_max'.");
			if(temp > 1) exit("Cannot load settings: circularity > 1.");
			temp_min = parseFloat(circularity_min);
			temp_max = parseFloat(circularity_max);	
			if(temp_max < temp_min) exit("Circularity maximum is lower than circularity minimum");
		
			result[12] = circularity_max;
		}


		// QC_measurement_name
		if(matches(line, regex_QC_measurement_name)){
			QC_measurement_name = replace(line, regex_QC_measurement_name, "${setting}");
			
			result[13] = QC_measurement_name;
		}


		// QC_measurement_min
		if(matches(line, regex_QC_measurement_min)){
			QC_measurement_min = replace(line, regex_QC_measurement_min, "${setting}");
			temp = parseFloat(QC_measurement_min);
			if(isNaN(temp))  exit("Error loading settings file: unexpected 'QC_measurement_min'.");
		
			result[14] = QC_measurement_min;
		}


		// QC_measurement_max
		if(matches(line, regex_QC_measurement_max)){
			QC_measurement_max = replace(line, regex_QC_measurement_max, "${setting}");
			temp = parseFloat(QC_measurement_max);
			if(isNaN(temp))  exit("Error loading settings file: unexpected 'QC_measurement_max'.");
			temp_min = parseFloat(QC_measurement_min);
			temp_max = parseFloat(QC_measurement_max);
			if(temp_max < temp_min) exit("QC maximum is lower than QC minimum");
			
			result[15] = QC_measurement_max;
		}
		
		
		// pixelsize
		if(matches(line, regex_pixelsize)){
			pixelsize = replace(line, regex_pixelsize, "${setting}");
			temp = parseFloat(pixelsize);
			if(isNaN(temp))  exit("Error loading settings file: unexpected 'pixelsize'.");
			if(temp < 0) exit("Cannot load settings: negative pixel size.");
		
			result[16] = pixelsize;
		}
	}

	return result;
}
