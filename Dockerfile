# Use the official Python image from Docker Hub
FROM python:3.9-slim

# Set the working directory inside the container
WORKDIR /app

# Copy the requirements.txt (we'll generate this in the next step)
COPY requirements.txt .

# Install the necessary dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the entire application directory to the container
COPY . .

# Expose the port that Flask will run on
EXPOSE 5000

# Set the environment variable for Flask to run in production
ENV FLASK_ENV=production

# Command to run the Flask application
CMD ["python", "app.py"]
