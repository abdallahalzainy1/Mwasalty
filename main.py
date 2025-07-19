import functions_framework
from vertexai.preview.generative_models import GenerativeModel
from flask import jsonify
import vertexai

vertexai.init(project="popu-5017d", location="us-central1")

@functions_framework.http
def getroutesai(request):
    try:
        request_json = request.get_json(silent=True)
        from_city = request_json.get("from")
        to_city = request_json.get("to")
        prompt = request_json.get("prompt")

        if not prompt:
            prompt = (
                f"Suggest 3 ways to travel from {from_city} to {to_city} in Egypt "
                f"including trains, microbuses, Uber, Careem, and metro. "
                f"Provide estimated time and price for each option in a simple clear format."
            )

        model = GenerativeModel("gemini-1.5-flash")
        response = model.generate_content(prompt)

        return jsonify({
            "response": response.text
        }), 200

    except Exception as e:
        return jsonify({
            "error": str(e)
        }), 500
