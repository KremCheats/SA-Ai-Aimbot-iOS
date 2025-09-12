
## Overview

This project provides a tool to analyze a game's screen in real-time using a CoreML model trained on YOLOv5. It captures the screen, runs object detection, and draws bounding boxes as an overlay.

![photo_5918232791361898398_y](https://github.com/user-attachments/assets/58961132-0690-45cf-aff1-fd663da6290d)
![photo_5918232791361898401_y](https://github.com/user-attachments/assets/67778e84-b2d2-49d7-a1b6-c4f42482bd41)
![photo_5918232791361898400_y](https://github.com/user-attachments/assets/4e42fc0f-e14f-47fd-b97e-f2a4ea95b95d)
![photo_5918232791361898399_y](https://github.com/user-attachments/assets/8b29e259-17f6-40af-ad66-f33f730455d1)


## Dataset Preparation

1. **Split Game Video into Frames**  
   - First, take a video of the game and split it into images at 1-second intervals.  
   - In this example, I worked with **5,000 images**, but the more images you have, the higher the accuracy.  
   - Don’t worry about the number of images — if you label them efficiently with **LabelImg** and optimize your keyboard shortcuts, you can finish labeling in a few hours.

2. **Train YOLOv5**  
   - After labeling, split the dataset **80/20** (80% training, 20% validation).  
   - Train YOLOv5 on the dataset to detect the objects you want.

3. **Convert YOLOv5 Model to CoreML**  
   - After training, export your YOLOv5 `.pt` model to **CoreML format (`.mlmodelc`)**.  
   - Place the resulting model in `Documents/SafeModel.mlmodelc` so the app can load it.

---

## How the Code Works

- **Initialization**:  
  The `ScreenAnalyzer` class is automatically initialized at app startup. It waits 1 second and then starts capturing the screen.

- **Screen Capture & Analysis**:  
  - A timer runs every `0.1s` (100ms).  
  - The current key window is captured and resized to **640x640** pixels.  
  - The captured image is sent to the CoreML model via a `VNCoreMLRequest`.  
  - The model outputs an `MLMultiArray` containing detected object coordinates and confidence scores.

- **Drawing Bounding Boxes**:  
  - The detected objects with confidence ≥ 0.5 are drawn as red rectangles on a transparent overlay on the screen.  
  - Maximum of 100 boxes are drawn per frame.  
  - The overlay updates only if the detection changes.

---

## Limitations

- Bounding boxes appear a few seconds after the object appears.  
- The system still needs optimization for real-time responsiveness.  

---

## Possible Improvements

- Integrate **auto-touch and swipe** actions to move the aim towards the detected bounding boxes, effectively creating an AIMBOT.  
- Optimize performance to reduce lag between detection and overlay rendering.  
- Expand dataset and improve labeling consistency for better accuracy.  

---

## Notes

- The more frames you label and train on, the better the detection accuracy.  
- Make sure to use a `.mlmodelc` compiled version of your CoreML model for faster inference.  
- The overlay is non-interactive and does not interfere with the game input.
