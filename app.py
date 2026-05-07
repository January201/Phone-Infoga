from flask import Flask, request, jsonify, render_template
import phonenumbers
from phonenumbers import carrier, geocoder, timezone

app = Flask(__name__)


def scan_number(input_number):
    formatted = "+" + input_number.strip().lstrip("+")
    try:
        parsed = phonenumbers.parse(formatted, None)
    except phonenumbers.NumberParseException as e:
        return None, str(e)

    if not phonenumbers.is_valid_number(parsed):
        return None, "Invalid phone number"

    country_code = phonenumbers.format_number(
        parsed, phonenumbers.PhoneNumberFormat.INTERNATIONAL
    ).split(" ")[0]

    local = phonenumbers.format_number(
        parsed, phonenumbers.PhoneNumberFormat.E164
    ).replace(country_code, "")

    result = {
        "international": phonenumbers.format_number(
            parsed, phonenumbers.PhoneNumberFormat.INTERNATIONAL
        ),
        "e164": phonenumbers.format_number(
            parsed, phonenumbers.PhoneNumberFormat.E164
        ),
        "local": local,
        "country_code": country_code,
        "country_iso": phonenumbers.region_code_for_country_code(int(country_code)),
        "country": geocoder.country_name_for_number(parsed, "en"),
        "location": geocoder.description_for_number(parsed, "en"),
        "carrier": carrier.name_for_number(parsed, "en"),
        "timezones": list(timezone.time_zones_for_number(parsed)),
        "valid": phonenumbers.is_valid_number(parsed),
        "possible": phonenumbers.is_possible_number(parsed),
        "number_type": _number_type(parsed),
    }
    return result, None


def _number_type(parsed):
    t = phonenumbers.number_type(parsed)
    types = {
        0: "Fixed line",
        1: "Mobile",
        2: "Fixed line or mobile",
        3: "Toll free",
        4: "Premium rate",
        5: "Shared cost",
        6: "VoIP",
        7: "Personal number",
        8: "Pager",
        9: "UAN",
        10: "Voicemail",
        99: "Unknown",
    }
    return types.get(t, "Unknown")


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/scan", methods=["POST"])
def scan():
    data = request.get_json()
    number = (data or {}).get("number", "").strip()
    if not number:
        return jsonify({"error": "Phone number is required"}), 400

    result, error = scan_number(number)
    if error:
        return jsonify({"error": error}), 400

    return jsonify(result)


if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5000)
