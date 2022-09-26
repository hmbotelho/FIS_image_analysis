// FIS Image Analysis Macro (batch analysis tool)
// ==================================
// 
// Required input data:
//   * Raw timelapse microscopy images of the FIS assay
//	 * The files being analyzed are defined by the regular expressions in lines 100-105
//	 * This macro works seamlessly with images renamed using the 'Transfer tool'
//
// Functionality:
//	 * Segments organoids, using a manual threshold and quality control parameters.
//   * Computes total organoid area per image, in a timelapse performed on a multi-well plate.
//   * Exports segmentation masks and *.csv data tables
// 
// 
// Author: Hugo M Botelho, BioISI/FCUL, University of Lisbon
// hmbotelho@fc.ul.pt
// October 2019
//
// -------------------------------------


// Segmentation variables
#@ String(value="=================== Segmentation settings ===================", visibility=MESSAGE) msg1
#@ String (label="Background filter", choices={"No Filter (flat background)", "Minimum", "Median", "Mean"}) bg_filter
#@ Integer (label="Radius of filter (if selected, pixel units)", value=80) radius_filter
#@ Float (label="Offset after background correction", value=0) subtract_offset
#@ Boolean (label="Sharpen image?", value=false) enhanceimage
#@ Float (label="Manual threshold value", value=0.1) threshold
#@ String (label="Fill all holes?", choices={"Never", "1st time point", "Always"}, style="radioButtonHorizontal") fillholes
#@ Boolean (label="Remove salt and pepper noise?", value=true) clean

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
#@ String (label="Regular expression matching all files being analyzed", value=".*--C01(?:\\.ome)??.tif$") regexfiles

// File locations
#@ String (value=" ", visibility=MESSAGE) msg8
#@ String (value="=================== Folder locations ===================", visibility=MESSAGE) msg9
#@ File (label="Raw FIS images", style="directory") sourcefolder
#@ File (label="Results", style="directory") targetfolder










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



// Save analysis settings
if(enhanceimage){
	enhanceimage_YN = "Yes";
} else{
	enhanceimage_YN = "No";
}
if(clean){
	clean_YN = "Yes";
} else{
	clean_YN = "No";
}
if(edge_exclude){
	edge_exclude_YN = "Yes";
} else{
	edge_exclude_YN = "No";
}

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
print(filehandle, "Sharpen image: " + enhanceimage_YN);
print(filehandle, "Manual threshold: " + threshold);
print(filehandle, "Fill all holes: " + fillholes);
print(filehandle, "Remove salt & pepper noise: " + clean_YN);
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



// Process variables
if(edge_exclude){
	i_edge_exclude = " exclude";
} else{
	i_edge_exclude = "";
}
if(fillholes == "Always"){
	i_fill = " include";
} else{
	i_fill = "";
}



// Close unnecessary windows
run("Close All");
closeWindow("Results");
closeWindow("Image quantification data");
print("\\Clear");



// Get file names
makeDirRecursive(targetfolder);
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
		file_masks = substring(file_masks, 0, lastIndexOf(file_masks, ".")) + "--masks.png";
		path_masks = folder_output + file_masks;


		
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
		segmentObjectsBF(bg_filter, radius_filter, subtract_offset, enhanceimage, threshold, clean, true);



		// Correlate the t and t-1 images.
		// This is to improve segmentation because the fluorescence signal is diluted out at late time points
		// A simple "fill holes" is not suitable: one has to discriminate between true holes (which must be filled) and gaps between objects (which must not)
		if(imgnum == 0){
		
			// Frame 1
			if(fillholes == "1st time point") run("Fill Holes");

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
		//run("Conversions...", " ");
		//run("8-bit");
		makeDirRecursive(folder_output);
		//saveAs("PNG", path_masks);
		saveAs("Tiff", path_masks);
		close();


		// Populate results table
		for(objnum=0; objnum<nResults; objnum++){
			ImageNumber            = ImageNumber;
			ObjectNumber           = objnum+1;
			Metadata_Channel       = Metadata_Channel;
			Metadata_FileLocation  = Metadata_FileLocation;
			Metadata_MaskLocation  = path_masks;
			Metadata_compound      = Metadata_compound;
			Metadata_concentration = Metadata_concentration;
			Metadata_imageBaseName = Metadata_imageBaseName;
			Metadata_pathBase      = Metadata_pathBase;
			Metadata_plateName     = Metadata_plateName;
			Metadata_platePath     = Metadata_platePath;
			Metadata_posNum        = Metadata_posNum;
			Metadata_posPath       = Metadata_posPath;
			Metadata_timeNum       = Metadata_timeNum;
			Metadata_wellNum       = Metadata_wellNum;
			Metadata_wellPath      = Metadata_wellPath;
			AreaShape_Center_X     = round(getResultString("X", objnum) / pixelsize);
			AreaShape_Center_Y     = round(getResultString("Y", objnum) / pixelsize);
			Math_area_micronsq     = getResultString("Area", objnum);
			TrackObjects_Label     = objnum+1;
			QC_value               = getResult(QC_measurement_heading, objnum);

			if(QC_measurement_name == QCmeasurementNamesPretty[0]){
				// QC has not been set. Accept the organoid in the dataset
				print(res, ImageNumber + "\t" + ObjectNumber + "\t" + Metadata_Channel + "\t" + Metadata_FileLocation + "\t" + Metadata_MaskLocation + "\t" + Metadata_compound + "\t" + Metadata_concentration + "\t" + Metadata_imageBaseName + "\t" + Metadata_pathBase + "\t" + Metadata_plateName + "\t" + Metadata_platePath + "\t" + Metadata_posNum + "\t" + Metadata_posPath + "\t" + Metadata_timeNum + "\t" + Metadata_wellNum + "\t" + Metadata_wellPath + "\t" + AreaShape_Center_X + "\t" + AreaShape_Center_Y + "\t" + Math_area_micronsq + "\t" + TrackObjects_Label);
			} else{
				// QC has been set. Only organoids meeting the criteria established by the user will be accepted
				if(QC_value >= QC_measurement_min && QC_value <= QC_measurement_max){
					print(res, ImageNumber + "\t" + ObjectNumber + "\t" + Metadata_Channel + "\t" + Metadata_FileLocation + "\t" + Metadata_MaskLocation + "\t" + Metadata_compound + "\t" + Metadata_concentration + "\t" + Metadata_imageBaseName + "\t" + Metadata_pathBase + "\t" + Metadata_plateName + "\t" + Metadata_platePath + "\t" + Metadata_posNum + "\t" + Metadata_posPath + "\t" + Metadata_timeNum + "\t" + Metadata_wellNum + "\t" + Metadata_wellPath + "\t" + AreaShape_Center_X + "\t" + AreaShape_Center_Y + "\t" + Math_area_micronsq + "\t" + TrackObjects_Label);
				}
			}

		}
		closeWindow("Results");


		// Rename image
		selectWindow(frame_name);
		rename("t-1");

	}

	// Save measurements for this folder
	selectWindow("Image quantification data");
	saveAs("Text", folder_output + "objects.csv");
	close("Image quantification data");


	// Close open images
	close("t-1");
	
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








































































//===================================================================================================
//   FUNCTIONS   ====================================================================================
//===================================================================================================


function segmentObjectsBF(bg_filter, radius_filter, subtract_offset, enhanceimage, threshold, clean, keepBgCorr) { 

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
	//imgname2 = "filtered_" + imgname;

	// 01 - Image pre-processing to 16-bit
	rename("01_16bit");
	run("Conversions...", " ");
	run("16-bit");

	// 02 - Background subtraction
	if(dofilter){
		run("Duplicate...", "title=02_Bg");
		run(bg_filter + "...", "radius=" + radius_filter);
		imageCalculator("Difference", "01_16bit", "02_Bg");
		close("02_Bg");
	}
	rename("03_BgCorr");
	
	// 03 - Rescale intensity to [0 ~ 1]
	run("32-bit");
	getRawStatistics(nPixels, mean, min, max); 
	range = max - min;
	run("Subtract...", "value=&min"); 
	run("Divide...", "value=&range");
	rename("04_rescaled");

	// 04 - Subtract offset (and strech intensities to [0 ~ 1]
	run("Subtract...", "value=" + subtract_offset);
	run("Multiply...", "value=" + 1/(1-subtract_offset));
	rename("05_bgCorrected");

	if(keepBgCorr){
		// Preserve the background-corrected image before segmentation
		// This is required for per-object intensity measurements (e.g. analyze particles)
		run("Duplicate...", "title=[bgCorr_" + imgname + "]");
	}
	selectWindow("05_bgCorrected");

	// 05 - Enhance image (unsharp mask)
	if(enhanceimage){
		run("Sharpen");
		rename("06_ehanced");
	}

	// 06 - Threshold
	setOption("BlackBackground", true);
	getRawStatistics(nPixels, mean, min, max);
	setThreshold(threshold, max);
	run("Make Binary");
	rename("07_thresholded");

	// 07 - Remove salt & pepper noise
	if(clean){
		run("Options...", "iterations=1 count=8 black pad do=Erode");
	}
	rename(imgname);

}


// Adapter function: enables using the listFilesRecursively() function properly
function listFiles(dir, regex, tempfile) {

	// Initialize a text file to temporarily store all filenames
	File.open(tempfile);
	
	// Call file listing function
	listFilesRecursively(dir, regex, tempfile);

	// Convert temporary file into array
	filestring = File.openAsString(tempfile);
	rows=split(filestring, "\n");
	File.delete(tempfile);
	
	return rows;
}


// Returns an array with all files matching the regular expression.
// Needs a temporary text file
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
function closeWindow(windowname){
	while(isOpen(windowname)){
		selectWindow(windowname);
		run("Close");
	}
}

// Creates a folder, recursively
function makeDirRecursive(dir){
	folders = split(dir, "/");
	temp = "";
	for(i=0; i<lengthOf(folders); i++){
		temp = temp + folders[i] + "/";
		if(!File.exists(temp)){
			File.makeDirectory(temp);
		}
	}
}


// This function adds a prefix to all elements of an array
function AppendPrefixArray (array, prefix){
	for (k=0; k<lengthOf(array); k++){
		array[k] = prefix + array[k];
	}
	return array;
}


// Subsets an array according to a regular expression
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


// Add padding zeroes
// https://imagej.nih.gov/ij/macros/misc/Conference%20Macros/07_Functions.ijm
  function leftPad(n, width) {
	s =""+n;
	while (lengthOf(s)<width)
		s = "0"+s;
	return s;
}


// Replaces all pixel values in a range by a single value
// Analogous magic wand + color fill
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
function formFactor(area, perimeter){
	FF = 4*PI*area/pow(perimeter, 2);
	return(FF);
}