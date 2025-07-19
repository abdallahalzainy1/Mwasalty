import functions_framework
from vertexai.preview.language_models import TextGenerationModel

@functions_framework.http
def getroutesai(request):  # ← الاسم ده لازم يكون بالضبط كده
    request_json = request.get_json()
    from_city = request_json.get("from")
    to_city = request_json.get("to")

    prompt = f"Suggest 3 ways to travel from {from_city} to {to_city} in Egypt. Include options like metro, train, microbus, Uber, or Careem with estimated prices and duration."

    model = TextGenerationModel.from_pretrained("gemini-1.5-flash-preview")
    response = model.predict(prompt, temperature=0.7)

    return {"routes": response.text}, 200
