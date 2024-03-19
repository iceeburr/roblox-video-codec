import qoi
import argparse
import cv2
import os
import shutil
import base64
import numpy as np
from tqdm import tqdm
from flask import Flask, send_file

def main(args):
    # Open the video file
    cap = cv2.VideoCapture('assets/examples/testgameplay.mp4')

    # Resize to 24fps@1024x576
    # for some god damn reason this bullshit doesn't work
    #cap.set(cv2.CAP_PROP_FPS, 24)
    #cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1024)
    #cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 576)

    # Define the total length of the video if available, otherwise set to None
    total_length = args.length if args.length is not None else int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    # Initialize the tqdm progress bar
    pbar = tqdm(total=total_length, desc="encoding video", unit="frame", dynamic_ncols=True)

    # Read the first frame
    cap.set(cv2.CAP_PROP_POS_FRAMES, args.startframe)
    ret, previous_frame = cap.read()
    if not ret:
        cap.release()
        raise Exception("failed to read video stream")

    frame_index = 1

    for filename in os.listdir('output'):
        file_path = os.path.join('output', filename)
        try:
            if os.path.isfile(file_path) or os.path.islink(file_path):
                os.unlink(file_path)
            elif os.path.isdir(file_path):
                shutil.rmtree(file_path)
        except Exception as e:
            print('failed to delete', e)

    def save_image(frame_to_save, frame_index):
        if args.method == 'jpeg':
            cv2.imwrite(os.path.join('output', f"{frame_index + 1}.jpg"), frame_to_save, [int(cv2.IMWRITE_JPEG_QUALITY), args.quality])
        elif args.method == 'qoi':
            qoi.write(os.path.join('output', f"{frame_index + 1}.qoi"), cv2.cvtColor(frame_to_save, cv2.COLOR_BGR2RGB))
        elif args.method == 'png':
            cv2.imwrite(os.path.join('output', f"{frame_index + 1}.png"), frame_to_save)
        else:
            cap.release()
            raise Exception("unknown image format")

    def process_frame(frame, frame_index):
        if args.delta:
            mask = np.any(previous_frame != frame, axis=-1)
            output = np.zeros_like(previous_frame)
            output[mask] = frame[mask]
            frame = output
        if args.grayscale and not args.method == 'qoi':
            save_image(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY), frame_index)
        else:
            save_image(frame, frame_index)

    # Save the first frame as a full image
    if args.grayscale and not args.method == 'qoi':
        save_image(cv2.cvtColor(previous_frame, cv2.COLOR_BGR2GRAY), 0)
    else:
        save_image(previous_frame, 0)
    pbar.update(1)

    # Process the rest of the frames
    while (args.length is None or frame_index < args.length):
        ret, frame = cap.read()
        if not ret:
            break
        process_frame(frame, frame_index)
        previous_frame = frame
        frame_index += 1
        pbar.update(1)

    # Release the video file
    cap.release()
    pbar.close()

# Server
app = Flask(__name__)

@app.route('/frame<int:index>')
def frame(index):
    # Send the image as a response
    return send_file(f'../output/{index}.jpg', mimetype='image/jpeg')

@app.route('/chunk<int:index>')
def chunk(index):
    chunk_size = 100
    start_index = (index - 1) * chunk_size + 1
    end_index = index * chunk_size + 1
    
    chunk_images = []
    no_images = True
    for i in range(start_index, end_index):
        image_path = f'output/{i}.jpg'
        if os.path.exists(image_path):
            no_images = False
            with open(image_path, 'rb') as image_file:
                encoded_image = base64.b64encode(image_file.read()).decode('utf-8')
                chunk_images.append(encoded_image)
        else:
            break

    if no_images:
        return '404 Not Found', 404
    else:
        return '\n'.join(chunk_images), 200, {'Content-Type': 'text/plain'}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='encode video')
    parser.add_argument('--method', choices=['png', 'qoi', 'jpeg'], default='jpeg', help='format for saving images')
    parser.add_argument('--quality', type=int, default=100, help='jpeg quality')
    parser.add_argument('--delta', action='store_true', help='enable delta compression method for saving images')
    parser.add_argument('--grayscale', action='store_true', help='convert the image to grayscale before saving')
    parser.add_argument('--server', action='store_true', help='run the server')
    parser.add_argument('--length', type=int, help='limit the number of frames to process')
    parser.add_argument('--startframe', type=int, default=0, help='set the start frame position')
    args = parser.parse_args()
    if args.server:
        app.run(port=3000)
    else:
        main(args)
