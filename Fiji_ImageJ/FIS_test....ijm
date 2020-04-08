// FIS Image Analysis Macro (Test mode)
// ==================================
// 
// 
// Licensed under the GNU General Public License v3.0 license
// https://github.com/hmbotelho/FIS_image_analysis
//
// Required input data:
//   * One raw timelapse microscopy image of the FIS assay
//	 * This macro requires an open image and will process the active one
//
// Functionality:
//   * Enables selecting parameters for the FIS Batch Image Analysis Macro.
//
//	 * Segments organoids, using a manual threshold and quality control parameters.
//   * Segmentation and quality control parameters can be tuned interactively.
//   * Displays segmentation results for user inspection.
//   * This is the sequence of image analysis steps:
//      1.  Duplicate raw image
//      2.  Convert to 16bit
//      3.  Compute a 'background-only' image (e.g. median filter)
//      4.  Subtract raw from background-only
//      5.  Rescale 0~1
//      6.  Subtract image offset (object fluorescence contributes to the background-only image)
//      7.  Manual thresholding
//      8.  Remove salt and pepper noise
//      9.  Apply quality control criteria
//      10. Display segmented organoids (segmentation masks)
// 
// Citation:
// Hagemeijer MC, Vonk AM, Awatade NT, Silva IAL, Tischer C, Hilsenstein V, Beekman JM, Amaral MD, Botelho HM (2020) An open-source high-content analysis workflow for CFTR function measurements using the forskolin-induced swelling assay. submitted
//
// Author: Hugo M Botelho, BioISI/FCUL, University of Lisbon
// hmbotelho@fc.ul.pt
// April 2020
//
// -------------------------------------


// Initialize variables
// Initialize QC
activeMeasurements = "mean standard modal min centroid perimeter fit shape feret's integrated median skewness redirect=bgCorrected decimal=3";
QCmeasurementNamesPretty   = newArray("None - Do not exclude", "Integrated density", "Mean gray value", "Median grayvalue", "Modal gray value", "Standard deviation grayvalues", "Minimum gray value", "Maximum gray value", "Perimeter", "Major ellipse axis", "Minor ellipse axis", "Circularity", "Ellipse aspect ratio", "Roundness", "Solidity", "Maximum caliper (Feret's diameter)", "Minimum caliper (Feret's diameter)", "Skewness", "Form Factor");
QCmeasurementNamesHeadings = newArray("",                      "IntDen",             "Mean",            "Median",           "Mode",             "StdDev",                        "Min",                "Max",                "Perim.",    "Major",              "Minor",              "Circ.",       "AR",                   "Round",     "Solidity", "Feret",                              "MinFeret",                           "Skew",     "FormFactor");
bg_filters = newArray("No Filter (flat background)", "Minimum", "Median", "Mean");
default_bg_filter = bg_filters[0];
default_radius_filter = 50;
default_subtract_offset = 0.005;
default_threshold = 0.05;
default_fillholes = false;
default_clean = true;
default_label_fontsize = 8;
default_area_min = 500;
default_area_max = 99999999;
default_edge_exclude = false;
default_circularity_min = 0.00;
default_circularity_max = 1.00;
default_QC_measurement_name = QCmeasurementNamesPretty[0];
default_QC_measurement_min = -999999;
default_QC_measurement_max = 999999;
default_pixelsize = 4.991;
testImageNames = newArray("raw", "16bit", "background", "bgCorr_withOffset", "bgCorr_withOffset_rescaled", "bgCorrected", "thresholded", "withoutSaltPepper", "organoids_beforeQC", "ORGANOIDS_FINAL")




// Check whether an image is open
openimages = getList("image.titles");
if(lengthOf(openimages) == 0){
	exit("There must be an open image");
}

// Establish which image to perform the test in
rawtitle = getTitle();



while(true) {

	// Check if the raw image is open
	openimages = getList("image.titles");
	foundraw = false;
	for(i=0; i < lengthOf(openimages); i++){
		if(openimages[i] == rawtitle){
			foundraw = true;
		}
	}
	if(foundraw == false){
		closeTestImages(testImageNames);
		exit("Raw image '" + rawtitle + "' is not open. Exiting macro!");
	}

	// Use a dialog box to get input from the user
	Dialog.create("FIS Analysis tool [Test Mode]");
	Dialog.addMessage("=================== Segmentation settings ===================");
	Dialog.addChoice("Background filter:", bg_filters, default_bg_filter);
	Dialog.addSlider("Radius of filter (if selected, pixel units):", 1, 1000, default_radius_filter);
	Dialog.addNumber("Offset after background correction:", default_subtract_offset);
	Dialog.addNumber("Manual threshold value:", default_threshold);
	Dialog.addCheckbox("Fill all holes?", default_fillholes);
	Dialog.addCheckbox("Remove salt and pepper noise?", default_clean);
	Dialog.addSlider("Font size for organoid labels", 5, 100, default_label_fontsize);
	Dialog.addMessage("");
	Dialog.addMessage("");
	Dialog.addMessage("");
	Dialog.addMessage("=================== Quality control ===================");
	Dialog.addCheckbox("Exclude objects touching the image border?", default_edge_exclude);
	Dialog.addNumber("Minimum organoid area (μm²):", default_area_min);
	Dialog.addNumber("Maximum organoid area (μm²):", default_area_max);
	Dialog.addSlider("Minimum organoid circularity", 0, 1, default_circularity_min) ;
	Dialog.addSlider("Maximum organoid circularity", 0, 1, default_circularity_max) ;
	Dialog.addMessage("");
	Dialog.addMessage("Exclude organoids based on measurements?");
	Dialog.addChoice("Measurement:", QCmeasurementNamesPretty, default_QC_measurement_name);
	Dialog.addNumber("Minimum allowed value:", default_QC_measurement_min);
	Dialog.addNumber("Maximum allowed value:", default_QC_measurement_max);
	Dialog.addMessage("");
	Dialog.addMessage("");
	Dialog.addMessage("");
	Dialog.addMessage("=================== Microscopy settings ===================");
	Dialog.addNumber("Pixel width/height (μm):", default_pixelsize);
	Dialog.show();



	// Get data from dialog
	
	// Segmentation variables
	bg_filter = Dialog.getChoice();
	radius_filter = Dialog.getNumber();
	subtract_offset = Dialog.getNumber();
	threshold = Dialog.getNumber();
	fillholes = Dialog.getCheckbox();
	clean = Dialog.getCheckbox();
	label_fontsize = Dialog.getNumber();
	
	// Quality control variables
	edge_exclude = Dialog.getCheckbox();
	size_min = Dialog.getNumber();
	size_max = Dialog.getNumber();
	circularity_min = Dialog.getNumber();
	circularity_max = Dialog.getNumber();
	QC_measurement_name = Dialog.getChoice();
	QC_measurement_min = Dialog.getNumber();
	QC_measurement_max = Dialog.getNumber();
	hindex = getArrayIndexes(QCmeasurementNamesPretty, QC_measurement_name);
	QC_measurement_heading = QCmeasurementNamesHeadings[hindex[0]];



	// Microscopy variables
	pixelsize = Dialog.getNumber();

	// Set values for when the window pops up again
	default_bg_filter = bg_filter;
	default_radius_filter = radius_filter;
	default_subtract_offset = subtract_offset;
	default_threshold = threshold;
	default_fillholes = fillholes;
	default_clean = clean;
	default_label_fontsize = label_fontsize;
	default_area_min = size_min;
	default_area_max = size_max;
	default_edge_exclude = edge_exclude;
	default_circularity_min = circularity_min;
	default_circularity_max = circularity_max;
	default_QC_measurement_name = QC_measurement_name;
	default_QC_measurement_min = QC_measurement_min;
	default_QC_measurement_max = QC_measurement_max;
	default_pixelsize = pixelsize;



	// Print chosen settings to the log window
	if(fillholes){
		fillholes_YN = "Yes";
	} else{
		fillholes_YN = "No";
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

	print("\\Clear");
	print("=============================================================================");
	print("FIS image analysis macro - Test mode");
	print("=============================================================================\n");
	print("Testing segmentation in image '" + rawtitle + "'");
	print("_____________________________________________________________________________\n");
	print("");
	print("Selected settings:");
	print("Background filter: " + bg_filter);
	if(bg_filter != "No Filter (flat background)"){
		print("Filter radius: " + radius_filter);
	}
	print("Image offset: " + subtract_offset);
	print("Manual threshold: " + threshold);
	print("Fill all holes: " + fillholes_YN);
	print("Remove salt&pepper noise: " + clean_YN);
	print("Exclude organoids touching the image border: " + edge_exclude_YN);
	print("Minimum allowed organoid size: " + size_min + " μm²");
	print("Maximum allowed organoid size: " + size_max + " μm²");
	print("Minimum allowed organoid circularity: " + circularity_min);
	print("Maximum allowed organoid circularity: " + circularity_max);
	print("[QC] Further exclude organoids based on the following measurement: " + QC_measurement_name);
	print("[QC] Minimum allowed measurement value: " + QC_measurement_min);
	print("[QC] Maximum allowed measurement value: " + QC_measurement_max);
	print("Pixel width/height: " + pixelsize + " μm");

	// Close open windows (if exist)
	closeTestImages(testImageNames);




	// Image segmentation beginning ======================
	
		// --- Create a duplicate of the raw image ---
		selectWindow(rawtitle);
		run("Duplicate...", "title=raw");
		run("Properties...", "unit=um pixel_width=" + pixelsize + " pixel_height=" + pixelsize);

		// --- Convert to 16bit ---
		// This makes the downstream analysis consistency regardles of raw images being, 8bit, 16bit, RGB, ...
		run("Duplicate...", "title=16bit");
		run("16-bit");
		run("Enhance Contrast", "saturated=0.35");

		if(bg_filter != "No Filter (flat background)"){

			// Apply filter to create a bacground-only image
			run("Duplicate...", "title=background");
			run(bg_filter + "...", "radius=" + radius_filter);
			run("Enhance Contrast", "saturated=0.35");

			// Subtract background-only from raw to generate a quasi-background-corrected image.
			// Background correction is not ideal because the background-only image contains a contribution fron objects (i.e. an offset)
			imageCalculator("Subtract create", "16bit","background");
			rename("bgCorr_withOffset");
			run("Enhance Contrast", "saturated=0.35");

		}

		// --- Rescale image ---
		// This improved handling of images where the background varies over time (e.g. bleaching)
		run("Duplicate...", "title=bgCorr_withOffset_rescaled");
		run("32-bit");
		getRawStatistics(nPixels, mean, min, max); 
		range = max - min;
		run("Subtract...", "value=&min"); 
		run("Divide...", "value=&range"); 
		run("Enhance Contrast", "saturated=0.35");

		// --- Subtract offset --- (and strech intensities to [0 ~ 1])
		run("Duplicate...", "title=bgCorrected");
		run("Subtract...", "value=" + subtract_offset);
		run("Multiply...", "value=" + 1/(1-subtract_offset));
		run("Enhance Contrast", "saturated=0.35");

		// --- Manual threshold ---
		run("Duplicate...", "title=thresholded");
		setOption("BlackBackground", true);
		getRawStatistics(nPixels, mean, min, max);
		setThreshold(threshold, max);
		run("Make Binary");

		// --- Remove salt & pepper noise --- (if required)
		if(clean){
			run("Duplicate...", "title=withoutSaltPepper");
			run("Options...", "iterations=1 count=8 black pad do=Erode");
		}
		
		// --- Analyze particles ---
		run("Duplicate...", "title=temp");

		// Determine how to deal with objects touching the image border
		if(edge_exclude){
			edgebehavior = " exclude";
		} else{
			edgebehavior = "";
		}
		if(fillholes){
			fillbehavior = " include";
		} else{
			fillbehavior = "";
		}
		
		run("Clear Results");
		close("Results");
		run("Set Measurements...", "area " + activeMeasurements);
		run("Analyze Particles...", "size=" + size_min + "-" + size_max + " circularity=" + circularity_min + "-" + circularity_max + " show=[Count Masks]" + edgebehavior + " display" + fillbehavior);
		run("glasbey_inverted");

		// --- Compute features not built in ImageJ
		for (r = 0; r < nResults; r++) {
			perimeter  = getResult("Perim.", r);
			area       = getResult("Area", r);
			FormFactor = formFactor(area, perimeter);

			setResult("FormFactor", r, FormFactor);
		}
		updateResults();




		if(QC_measurement_name == QCmeasurementNamesPretty[0]){
			rename("ORGANOIDS_FINAL");
		} else{
			rename("organoids_beforeQC");

		// --- Object-based QC ---
			run("Duplicate...", "title=ORGANOIDS_FINAL");

			// Get the QC measurement value for each organoid
			for (i = 0; i < nResults; i++) {
				QC_value = getResult(QC_measurement_heading, i);

				// Hide objects which do not satisfy the QC criteria
				if(QC_value < QC_measurement_min || QC_value > QC_measurement_max){
					ReplacePixelValues(i+1, i+1, 0);
				}
			}
			
		}
		close("temp");
		run("Set Measurements...", replace("area " + activeMeasurements, "redirect=bgCorrected", "redirect=None"));

		

		// --- Overlay object ID on images ---
		// For each organoid: get label and coordinate
		// Label approved and rejected organoids with different colors
		centroidX_approved = newArray();
		centroidY_approved = newArray();
		labels_approved = newArray();
		centroidX_rejected = newArray();
		centroidY_rejected = newArray();
		labels_rejected = newArray();

		for (i = 0; i < nResults; i++) {
			centroidX = round(getResult("X", i)/pixelsize);
			centroidY = round(getResult("Y", i)/pixelsize);
			label = i+1;
			QC_value = getResult(QC_measurement_heading, i);

			if(QC_measurement_name == QCmeasurementNamesPretty[0]){

				// Approve all organoids
				centroidX_approved = Array.concat(centroidX_approved, centroidX);
				centroidY_approved = Array.concat(centroidY_approved, centroidY);
				labels_approved = Array.concat(labels_approved, label);
				
			} else{
				
				// Organoids are approved or rejected depending on QC parameters
				if(QC_value < QC_measurement_min || QC_value > QC_measurement_max){
					centroidX_rejected = Array.concat(centroidX_rejected, centroidX);
					centroidY_rejected = Array.concat(centroidY_rejected, centroidY);
					labels_rejected = Array.concat(labels_rejected, label);
				} else{
					centroidX_approved = Array.concat(centroidX_approved, centroidX);
					centroidY_approved = Array.concat(centroidY_approved, centroidY);
					labels_approved = Array.concat(labels_approved, label);
				}
				
			}
			
		}
		
		// Label objects
		// Approved objects: cyan color
		// Rejected objects: red color
		for(i = 0; i < lengthOf(testImageNames); i++){
			if(isOpen(testImageNames[i])){
				selectWindow(testImageNames[i]);
				addOverlays(centroidX_approved, centroidY_approved, labels_approved, label_fontsize, "cyan");
				addOverlays(centroidX_rejected, centroidY_rejected, labels_rejected, label_fontsize, "red");
			}
		}



		// --- Overlay QC measurements ---
		// This works by removing the labels overlay and replacing them by the QC measurements
		if(QC_measurement_name != QCmeasurementNamesPretty[0]){
			selectWindow("organoids_beforeQC");
			run("Remove Overlay");
			addOverlay(5, 5, "Showing values for: " + QC_measurement_name, label_fontsize * 2, "white");

			// For each organoid: get label and coordinate
			// Label approved and rejected organoids with different colors
			centroidX_approved = newArray();
			centroidY_approved = newArray();
			labels_approved = newArray();
			centroidX_rejected = newArray();
			centroidY_rejected = newArray();
			labels_rejected = newArray();
			
			for (i = 0; i < nResults; i++) {
				centroidX = round(getResult("X", i)/pixelsize);
				centroidY = round(getResult("Y", i)/pixelsize);
				label = getResult(QC_measurement_heading, i);

				if(label < QC_measurement_min || label > QC_measurement_max){
					centroidX_rejected = Array.concat(centroidX_rejected, centroidX);
					centroidY_rejected = Array.concat(centroidY_rejected, centroidY);
					labels_rejected = Array.concat(labels_rejected, label);
				} else{
					centroidX_approved = Array.concat(centroidX_approved, centroidX);
					centroidY_approved = Array.concat(centroidY_approved, centroidY);
					labels_approved = Array.concat(labels_approved, label);
				}
				
			}
			
			// Label objects
			// Approved objects: cyan color
			// Rejected objects: red color
			addOverlays(centroidX_approved, centroidY_approved, labels_approved, label_fontsize, "cyan");
			addOverlays(centroidX_rejected, centroidY_rejected, labels_rejected, label_fontsize, "red");
			
		}
		

		


	// Image segmentation end ======================




	// Number images for easier visual inspection
	numberTestImages(testImageNames);
	
	

	// Prepare images for inspection
	run("Tile");
	waitForUser("You may inspect the segmentation of test image '" + rawtitle + "'\n\nNumeric labels can be hidden in 'image > overlay > Hide Overlay'");
	close("Results");
}










// ================ Helper Functions ================


function numberTestImages(array){

	openimgs = getList("image.titles");
	n = 0;

	for(i=0; i<lengthOf(array); i++){
		for(j=0; j<lengthOf(openimgs); j++){
			if(openimgs[j] == array[i]){
				selectWindow(openimgs[j]);
				rename(n + "_" + openimgs[j]);
				n++;
			}
		}
	}	
}





function closeTestImages(array){

	openimgs = getList("image.titles");

	for(i=0; i<lengthOf(array); i++){
		for(j=0; j<lengthOf(openimgs); j++){
			if(matches(openimgs[j], "(\\d)*_" + array[i])){
				close(openimgs[j]);
			}
		}
	}	
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





// Adds a single text overlay to an image.
// Labels and coordinates are specified as numbers and strings
// The (x,y) values are the the top left coordinate of the label, unless 
function addOverlay(x, y, label, fontsize, color){

	// Initialize overlay settings
	setFont("SansSerif", fontsize, " antialiased");
	setColor(color);

	// Compute label coordinates
	x_offset = x - 0.080513589 * fontsize + 0.031484715;
	y_offset = y + 0.936729762 * fontsize + 1.525775272;
	
	// Overlay text
	Overlay.drawString(label, x_offset, y_offset, 0.0);
	Overlay.show();
}





// Adds a text overlay to an image.
// Labels and coordinates are specified as arrays
// Labels appear centered at the (x,y) values specified in the corresponding arrays
function addOverlays(arrayX, arrayY, arrayLabels, fontsize, color){

	// Initialize overlay settings
	setFont("SansSerif", fontsize, " antialiased");
	setColor(color);

	// Get information about the image
	imgWidth = getWidth();
	imgHeight = getHeight();

	for (i = 0; i < lengthOf(arrayX); i++) {
		x = arrayX[i];
		y = arrayY[i];
		l = toString(arrayLabels[i]);
		nchar = lengthOf(l);

		// Compute coordinates for centered text
		x_slope = 0.275697157*nchar+0.001428863;
		x_intercept = 0.045703194*nchar-0.527401065;
		x_offset = x - (x_slope*fontsize+x_intercept);
		y_offset = y + (0.57589712*fontsize+1.415686537);
		if(x_offset < 0) x_offset = 0;
		if(x_offset > imgWidth) x_offset = imgWidth;
		if(y_offset < 0) y_offset = 0;
		if(y_offset > imgHeight) y_offset = imgHeight;
		
		// Overlay text
		Overlay.drawString(l, x_offset, y_offset, 0.0);
		Overlay.show();
	}
	
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
