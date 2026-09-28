FROM pytorch/pytorch:2.6.0-cuda12.4-cudnn9-runtime
WORKDIR /opt/project
COPY model-improvement/stack-heatmap/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt
COPY model-improvement/stack-heatmap /opt/project/model-improvement/stack-heatmap
COPY backend/app/vision/heatmap_model.py /opt/project/backend/app/vision/heatmap_model.py
ENV SM_CHECKPOINT_DIR=/opt/ml/checkpoints
ENTRYPOINT ["python", "/opt/project/model-improvement/stack-heatmap/aws/train_entrypoint.py"]
