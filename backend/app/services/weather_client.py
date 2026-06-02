"""Weather client that fetches real forecasts via Open-Meteo (free, no API key).

Open-Meteo provides free weather forecasts with geocoding. This keeps the Agent
independent of paid weather providers while still returning real data.
"""

from dataclasses import dataclass
from datetime import date, timedelta
from typing import Any

import httpx

# WMO weather-code → wardrobe taxonomy weather_type mapping.
# https://www.nodc.noaa.gov/archive/arc0021/0002199/1.1/data/0-data/HTML/WMO-CODE/WMO4677.HTM
_WMO_CODE_TO_WEATHER_TYPE: dict[int, str] = {
    0: "clear",
    1: "clear",
    2: "cloudy",
    3: "cloudy",
    45: "cloudy",
    48: "cloudy",
    51: "rain",
    53: "rain",
    55: "rain",
    56: "rain",
    57: "rain",
    61: "rain",
    63: "rain",
    65: "rain",
    66: "rain",
    67: "rain",
    71: "snow",
    73: "snow",
    75: "snow",
    77: "snow",
    80: "rain",
    81: "rain",
    82: "rain",
    85: "snow",
    86: "snow",
    95: "rain",
    96: "rain",
    99: "rain",
}


@dataclass(frozen=True)
class WeatherForecast:
    """A single-day forecast mapped to wardrobe taxonomy vocabulary."""

    city: str | None  # None when looked up by coordinates alone
    forecast_date: date
    temperature_max: float
    temperature_min: float
    weather_type: str  # one of taxonomy weatherTypes keys
    precipitation: float  # mm
    wind_speed: float  # km/h
    source: str  # "coordinates" or "geocoding"


class WeatherClient:
    """Fetches weather forecasts from Open-Meteo.

    Open-Meteo is a free, no-key-required weather API. This client:
    1. Geocodes a city name → coordinates via the Open-Meteo geocoding API.
    2. Fetches a daily forecast for the target date.
    3. Maps WMO weather codes to wardrobe taxonomy weather_type values.
    """

    GEOCODING_URL = "https://geocoding-api.open-meteo.com/v1/search"
    FORECAST_URL = "https://api.open-meteo.com/v1/forecast"

    def __init__(self, timeout_seconds: float = 15.0) -> None:
        """Initializes the Open-Meteo client.

        Args:
            timeout_seconds: HTTP request timeout in seconds.
        """
        self.timeout = timeout_seconds

    # ------------------------------------------------------------------
    # public API
    # ------------------------------------------------------------------

    def fetch_forecast(
        self,
        target_date: date,
        *,
        city: str | None = None,
        latitude: float | None = None,
        longitude: float | None = None,
    ) -> WeatherForecast | None:
        """Fetches a forecast for *target_date* at the given location.

        Priority: coordinates (lat/lon) → city geocoding → None.

        Returns ``None`` when:
        - Neither coordinates nor a city name is provided.
        - The city cannot be geocoded.
        - The target date is beyond the forecast window (typically 16 days).

        Raises ``WeatherClientError`` on network / timeout failures.
        """
        # ── resolve coordinates ────────────────────────────────────
        if latitude is not None and longitude is not None:
            lat, lon = float(latitude), float(longitude)
            source = "coordinates"
        elif city is not None:
            coords = self._geocode(city)
            if coords is None:
                return None
            lat, lon = coords
            source = "geocoding"
        else:
            return None

        daily = self._fetch_daily_forecast(lat, lon, target_date)
        if daily is None:
            return None

        return WeatherForecast(
            city=city,
            forecast_date=target_date,
            temperature_max=float(daily["temperature_2m_max"]),
            temperature_min=float(daily["temperature_2m_min"]),
            weather_type=_wmo_to_weather_type(int(daily["weather_code"])),
            precipitation=float(daily.get("precipitation_sum", 0.0)),
            wind_speed=float(daily.get("wind_speed_10m_max", 0.0)),
            source=source,
        )

    # ------------------------------------------------------------------
    # internal helpers
    # ------------------------------------------------------------------

    def _geocode(self, city: str) -> tuple[float, float] | None:
        """Resolves *city* to (latitude, longitude)."""
        try:
            with httpx.Client(timeout=self.timeout) as client:
                response = client.get(
                    self.GEOCODING_URL,
                    params={
                        "name": city,
                        "count": 1,
                        "language": "zh",
                        "format": "json",
                    },
                )
                response.raise_for_status()
                body: dict[str, Any] = response.json()
        except httpx.HTTPError:
            raise WeatherClientError(f"Geocoding request failed for city={city!r}")

        results = body.get("results")
        if not results:
            return None
        return float(results[0]["latitude"]), float(results[0]["longitude"])

    def _fetch_daily_forecast(
        self,
        lat: float,
        lon: float,
        target_date: date,
    ) -> dict[str, Any] | None:
        """Fetches the daily forecast and picks the row for *target_date*."""
        today = date.today()
        forecast_days = max((target_date - today).days + 1, 1)

        try:
            with httpx.Client(timeout=self.timeout) as client:
                response = client.get(
                    self.FORECAST_URL,
                    params={
                        "latitude": lat,
                        "longitude": lon,
                        "daily": (
                            "temperature_2m_max,temperature_2m_min,"
                            "precipitation_sum,weather_code,wind_speed_10m_max"
                        ),
                        "timezone": "auto",
                        "forecast_days": forecast_days,
                    },
                )
                response.raise_for_status()
                body: dict[str, Any] = response.json()
        except httpx.HTTPError:
            raise WeatherClientError(
                f"Forecast request failed for lat={lat}, lon={lon}"
            )

        daily = body.get("daily")
        if not daily:
            return None

        dates: list[str] = daily.get("time", [])
        target_iso = target_date.isoformat()
        try:
            idx = dates.index(target_iso)
        except ValueError:
            return None

        return {
            key: values[idx]
            for key, values in daily.items()
            if isinstance(values, list)
        }


class WeatherClientError(RuntimeError):
    """Raised when a weather provider request fails (network, timeout, etc.)."""


# ------------------------------------------------------------------
# WMO code mapping
# ------------------------------------------------------------------


def _wmo_to_weather_type(code: int) -> str:
    """Maps a WMO weather code to wardrobe weather taxonomy.

    Args:
        code: Numeric WMO weather code.

    Returns:
        Wardrobe `weather_type` value.
    """
    return _WMO_CODE_TO_WEATHER_TYPE.get(code, "cloudy")


# ------------------------------------------------------------------
# Fake client for tests
# ------------------------------------------------------------------


class FakeWeatherClient(WeatherClient):
    """A test double that returns controlled forecasts without network calls."""

    def __init__(
        self,
        *,
        forecast: WeatherForecast | None = None,
        fail_with: Exception | None = None,
    ) -> None:
        """Initializes the fake weather client.

        Args:
            forecast: Forecast to return from `fetch_forecast`.
            fail_with: Exception to raise from `fetch_forecast`.
        """
        super().__init__()
        self._forecast = forecast
        self._fail_with = fail_with
        self.last_call_kwargs: dict[str, Any] | None = None

    def fetch_forecast(
        self,
        target_date: date,
        *,
        city: str | None = None,
        latitude: float | None = None,
        longitude: float | None = None,
    ) -> WeatherForecast | None:
        """Returns the configured fake forecast or raises the fake error.

        Args:
            target_date: Requested forecast date.
            city: Optional city name.
            latitude: Optional latitude.
            longitude: Optional longitude.

        Returns:
            Configured fake forecast or None.
        """
        self.last_call_kwargs = {
            "target_date": target_date,
            "city": city,
            "latitude": latitude,
            "longitude": longitude,
        }
        if self._fail_with is not None:
            raise self._fail_with
        return self._forecast
