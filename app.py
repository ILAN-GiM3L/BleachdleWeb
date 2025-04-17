from flask import Flask, render_template, request, jsonify
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import time
import mysql.connector
import requests
import os
from dotenv import load_dotenv

# Load Dotenv
load_dotenv()

app = Flask(__name__)

### PROMETHEUS >>>
REQUEST_COUNT = Counter(
    "bleachdle_request_total", "Total HTTP requests", ["method", "endpoint", "http_status"]
)
REQUEST_LATENCY = Histogram(
    "bleachdle_request_latency_seconds", "Request latency", ["endpoint"]
)
### PROMETHEUS <<<

# MySQL connection configuration for Google Cloud
db_config = {
    'host': os.getenv('DB_HOST'),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD'),
    'database': os.getenv('DB_NAME')
}

# Route to get today's character data from the API
def get_todays_character():
    response = requests.get(f"{os.getenv('API_URL')}/character")
    # Check if the response status is OK (200)
    if response.status_code == 200:
        data = response.json()
        # Ensure the 'character' key exists and return the data
        if 'character' in data:
            return data['character']  # Returning only the 'character' part
    return None

def get_todays_bankai():
    response = requests.get(f"{os.getenv('API_URL')}/bankai")
    if response.status_code == 200:
        return response.json()
    return None

def get_todays_schrift():
    response = requests.get(f"{os.getenv('API_URL')}/schrift")
    if response.status_code == 200:
        return response.json()
    return None


### PROMETHEUS-ADD >>>
@app.before_request
def start_timer():
    request.start_time = time.time()

@app.after_request
def record_metrics(response):
    latency = time.time() - getattr(request, "start_time", time.time())
    REQUEST_LATENCY.labels(request.path).observe(latency)
    REQUEST_COUNT.labels(request.method, request.path, response.status_code).inc()
    return response

@app.route("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}
### PROMETHEUS-ADD <<<



@app.route('/')
def main_page():
    # This route renders the main page with buttons
    return render_template('main.html')

@app.route('/character')
def character():
    # This route renders the main.html file
    return render_template('character.html')

@app.route('/bankai')
def bankai():
    return render_template('bankai.html')

@app.route('/schrift')
def schrift():
    return render_template('schrift.html')

@app.route('/search_characters')
def search_characters():
    # Get the query string from the URL
    query = request.args.get('query', '').strip()

    if not query:
        return jsonify([])  # If no query is entered, return an empty list
    
    # Create a connection to MySQL database
    conn = mysql.connector.connect(**db_config)
    cursor = conn.cursor(dictionary=True)
    
    # Query the database for character names that start with the query string
    cursor.execute("""
        SELECT chr_name
        FROM bleach_characters 
        WHERE chr_name LIKE %s 
        OR chr_name LIKE CONCAT('% ', %s)
    """, (f'{query}%', f'{query}%'))  # Match both first name and last name
    
    # Fetch all the results that match
    results = cursor.fetchall()
    
    # Close the cursor and connection after the query
    cursor.close()
    conn.close()

    return jsonify(results)  # Return the results as JSON

@app.route('/compare_character', methods=['POST'])
def compare_character():
    selected_character = request.json.get('selected_character')  # Selected character's name

    # Get today's character
    todays_character = get_todays_character()
    if not todays_character:
        return jsonify({"error": "Unable to fetch today's character"})

    # Fetch character data from the database
    conn = mysql.connector.connect(**db_config)
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT * FROM bleach_characters WHERE chr_name = %s", (selected_character,))
    character_data = cursor.fetchone()
    cursor.close()
    conn.close()

    if not character_data:
        return jsonify({"error": "Character not found in the database"})

    # Compare the selected character attributes with today's character attributes
    comparison_result = {}
    for key, value in character_data.items():
        if key != 'chr_name':  # We don't compare 'chr_name' directly here
            comparison_result[key] = {
                'value': value,
                'is_correct': value == todays_character.get(key)
            }

    return jsonify({
        "character_data": character_data,
        "comparison_result": comparison_result,
        "todays_character": todays_character
    })

@app.route('/compare_bankai', methods=['POST'])
def compare_bankai():
    selected_character = request.json.get('selected_character')  # Selected character's name

    # Get today's Bankai data (including chr_id)
    todays_bankai = get_todays_bankai()
    if not todays_bankai:
        return jsonify({"error": "Unable to fetch today's Bankai"})

    todays_chr_id = todays_bankai.get('bankai', {}).get('chr_id')  # Get the chr_id for today's Bankai
    if not todays_chr_id:
        return jsonify({"error": "Today's Bankai data is incomplete"})

    # Fetch character data from the database based on the chr_name
    conn = mysql.connector.connect(**db_config)
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT * FROM bleach_characters WHERE chr_name = %s", (selected_character,))
    character_data = cursor.fetchone()
    cursor.close()
    conn.close()

    if not character_data:
        return jsonify({"error": "Character not found in the database"})

    # Compare the selected character's chr_id with today's Bankai's chr_id
    is_correct = character_data['chr_id'] == todays_chr_id

    return jsonify({
        "character_data": character_data,
        "is_correct": is_correct,  # Return a flag indicating if the selection is correct
        "todays_bankai_chr_id": todays_chr_id
    })

@app.route('/compare_schrift', methods=['POST'])
def compare_schrift():
    selected_character = request.json.get('selected_character')  # Selected character's name

    # Get today's Bankai data (including chr_id)
    todays_schrift = get_todays_schrift()
    if not todays_schrift:
        return jsonify({"error": "Unable to fetch today's Schrift"})

    todays_chr_id = todays_schrift.get('schrift', {}).get('chr_id')  # Get the chr_id for today's Bankai
    if not todays_chr_id:
        return jsonify({"error": "Today's Schrift data is incomplete"})

    # Fetch character data from the database based on the chr_name
    conn = mysql.connector.connect(**db_config)
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT * FROM bleach_characters WHERE chr_name = %s", (selected_character,))
    character_data = cursor.fetchone()
    cursor.close()
    conn.close()

    if not character_data:
        return jsonify({"error": "Character not found in the database"})

    # Compare the selected character's chr_id with today's Bankai's chr_id
    is_correct = character_data['chr_id'] == todays_chr_id

    return jsonify({
        "character_data": character_data,
        "is_correct": is_correct,  # Return a flag indicating if the selection is correct
        "todays_schrift_chr_id": todays_chr_id
    })

@app.route('/get_todays_bankai_data')
def get_todays_bankai_data():
    # Get today's Bankai data (this function was already in your app)
    todays_bankai = get_todays_bankai()
    
    # Return the Bankai data as JSON
    if todays_bankai and 'bankai' in todays_bankai:
        return jsonify(todays_bankai)
    
    return jsonify({'error': 'Unable to fetch Bankai data'})


@app.route('/get_todays_schrift_data')
def get_todays_schrift_data():
    # Get today's Bankai data (this function was already in your app)
    todays_schrift = get_todays_schrift()
    
    # Return the Bankai data as JSON
    if todays_schrift and 'schrift' in todays_schrift:
        return jsonify(todays_schrift)
    
    return jsonify({'error': 'Unable to fetch Schrift data'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)


