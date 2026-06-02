"""Tests for the weather node: state updates and data flow.

The core question: after _get_weather executes, does the LangGraph state
contain real weather data for the target location?

Priority: GPS coordinates → city geocoding → skip.
Uses FakeWeatherClient to control upstream data and verify every state
transition (success, no-location, provider-error, unavailable).
"""

from datetime import date
from uuid import uuid4

import pytest

from app.schemas.agent import OutfitRecommendationRequest
from app.services.agent_llm_service import OpenAICompatibleChatClient
from app.services.clothing_taxonomy import get_clothing_taxonomy
from app.services.outfit_agent_service import OutfitRecommendationAgent
from app.services.weather_client import (
    FakeWeatherClient,
    WeatherClientError,
    WeatherForecast,
)


# ── helpers ────────────────────────────────────────────────────────────────


def _forecast(**kw) -> WeatherForecast:
    """Builds a WeatherForecast with defaults for every field."""
    defaults = {
        "city": "上海",
        "forecast_date": date(2026, 6, 3),
        "temperature_max": 28.0,
        "temperature_min": 22.0,
        "weather_type": "rain",
        "precipitation": 12.5,
        "wind_speed": 18.0,
        "source": "geocoding",
    }
    defaults.update(kw)
    return WeatherForecast(**defaults)


def _state(*, city="上海", latitude=None, longitude=None,
           target_date=date(2026, 6, 3), **kw):
    """Minimal OutfitAgentState for node unit tests."""
    return {
        "db": None,
        "user_id": uuid4(),
        "request": OutfitRecommendationRequest(
            message="今天穿什么",
            city=city,
            latitude=latitude,
            longitude=longitude,
            targetDate=target_date,
            **kw,
        ),
        "tools": {},
    }


# ── success: state gets real weather data (city path) ──────────────────────


class TestGetWeatherSuccess:
    """When the provider returns a forecast via city, state must carry that data."""

    def test_status_is_success(self):
        """Verifies status is success."""
        fc = _forecast()
        agent = OutfitRecommendationAgent(weather_client=FakeWeatherClient(forecast=fc))
        result = agent._get_weather(_state())
        assert result["tools"]["get_weather"].status == "success"

    def test_weather_context_has_city(self):
        """Verifies weather context has city."""
        fc = _forecast(city="深圳")
        agent = OutfitRecommendationAgent(weather_client=FakeWeatherClient(forecast=fc))
        result = agent._get_weather(_state(city="深圳"))
        assert result["weather_context"]["city"] == "深圳"

    def test_weather_context_has_target_date(self):
        """Verifies weather context has target date."""
        fc = _forecast(forecast_date=date(2026, 8, 15))
        agent = OutfitRecommendationAgent(weather_client=FakeWeatherClient(forecast=fc))
        result = agent._get_weather(_state(target_date=date(2026, 8, 15)))
        assert result["weather_context"]["targetDate"] == "2026-08-15"

    def test_weather_context_has_temperature(self):
        """Verifies weather context has temperature."""
        fc = _forecast(temperature_max=32.5, temperature_min=26.0)
        agent = OutfitRecommendationAgent(weather_client=FakeWeatherClient(forecast=fc))
        result = agent._get_weather(_state())
        assert result["weather_context"]["temperatureMax"] == 32.5
        assert result["weather_context"]["temperatureMin"] == 26.0

    def test_weather_context_has_weather_type(self):
        """Verifies weather context has weather type."""
        fc = _forecast(weather_type="snow")
        agent = OutfitRecommendationAgent(weather_client=FakeWeatherClient(forecast=fc))
        result = agent._get_weather(_state())
        assert result["weather_context"]["weatherType"] == "snow"

    def test_weather_context_has_precipitation(self):
        """Verifies weather context has precipitation."""
        fc = _forecast(precipitation=25.0)
        agent = OutfitRecommendationAgent(weather_client=FakeWeatherClient(forecast=fc))
        result = agent._get_weather(_state())
        assert result["weather_context"]["precipitation"] == 25.0

    def test_weather_context_has_wind_speed(self):
        """Verifies weather context has wind speed."""
        fc = _forecast(wind_speed=30.0)
        agent = OutfitRecommendationAgent(weather_client=FakeWeatherClient(forecast=fc))
        result = agent._get_weather(_state())
        assert result["weather_context"]["windSpeed"] == 30.0

    def test_weather_context_has_source(self):
        """Verifies weather context has source."""
        fc = _forecast()
        agent = OutfitRecommendationAgent(weather_client=FakeWeatherClient(forecast=fc))
        result = agent._get_weather(_state())
        assert result["weather_context"]["source"] == "open-meteo"

    def test_weather_context_has_source_type(self):
        """Verifies weather context has source type."""
        fc = _forecast(source="geocoding")
        agent = OutfitRecommendationAgent(weather_client=FakeWeatherClient(forecast=fc))
        result = agent._get_weather(_state())
        assert result["weather_context"]["sourceType"] == "geocoding"

    def test_agent_message_includes_temperature(self):
        """Verifies agent message includes temperature."""
        fc = _forecast(temperature_min=20.0, temperature_max=30.0)
        agent = OutfitRecommendationAgent(weather_client=FakeWeatherClient(forecast=fc))
        result = agent._get_weather(_state())
        msg = result["tools"]["get_weather"].message_for_agent
        assert "20" in msg
        assert "30" in msg

    def test_user_message_includes_city_and_weather_type(self):
        """Verifies user message includes city and weather type."""
        fc = _forecast(city="北京", weather_type="clear")
        agent = OutfitRecommendationAgent(weather_client=FakeWeatherClient(forecast=fc))
        result = agent._get_weather(_state(city="北京"))
        user_msg = result["tools"]["get_weather"].message_for_user or ""
        assert "北京" in user_msg
        assert "clear" in user_msg

    def test_state_preserves_existing_tools(self):
        """Verifies state preserves existing tools."""
        fc = _forecast()
        agent = OutfitRecommendationAgent(weather_client=FakeWeatherClient(forecast=fc))
        state = _state()
        from app.schemas.agent import AgentToolResult
        prior = AgentToolResult(status="success", data={"x": 1})
        state["tools"]["prior_node"] = prior
        result = agent._get_weather(state)
        assert result["tools"]["prior_node"] is prior
        assert "get_weather" in result["tools"]


# ── success: GPS coordinates path ─────────────────────────────────────────


class TestGetWeatherWithCoordinates:
    """When lat/lon are provided, weather is fetched without geocoding."""

    def test_coordinates_produce_success(self):
        """Verifies coordinates produce success."""
        fc = _forecast(city=None, source="coordinates")
        fake = FakeWeatherClient(forecast=fc)
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state(city=None, latitude=28.2282, longitude=112.9388))
        assert result["tools"]["get_weather"].status == "success"

    def test_coordinates_pass_through_to_client(self):
        """FakeWeatherClient must receive the exact lat/lon from the request."""
        fc = _forecast(city=None, source="coordinates")
        fake = FakeWeatherClient(forecast=fc)
        agent = OutfitRecommendationAgent(weather_client=fake)
        agent._get_weather(_state(city=None, latitude=39.9042, longitude=116.4074))
        assert fake.last_call_kwargs is not None
        assert fake.last_call_kwargs["latitude"] == 39.9042
        assert fake.last_call_kwargs["longitude"] == 116.4074

    def test_coordinates_skip_geocoding(self):
        """When lat/lon are given, city=None is passed to the client (no geocoding)."""
        fc = _forecast(city=None, source="coordinates")
        fake = FakeWeatherClient(forecast=fc)
        agent = OutfitRecommendationAgent(weather_client=fake)
        agent._get_weather(_state(city=None, latitude=28.2282, longitude=112.9388))
        assert fake.last_call_kwargs is not None
        assert fake.last_call_kwargs["city"] is None

    def test_coordinates_priority_over_city(self):
        """When BOTH lat/lon AND city are given, coordinates take priority."""
        fc = _forecast(city="上海", source="coordinates")
        fake = FakeWeatherClient(forecast=fc)
        agent = OutfitRecommendationAgent(weather_client=fake)
        agent._get_weather(_state(city="上海", latitude=28.2282, longitude=112.9388))
        assert fake.last_call_kwargs is not None
        assert fake.last_call_kwargs["latitude"] == 28.2282
        assert fake.last_call_kwargs["longitude"] == 112.9388

    def test_source_type_is_coordinates(self):
        """Verifies source type is coordinates."""
        fc = _forecast(city=None, source="coordinates")
        fake = FakeWeatherClient(forecast=fc)
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state(city=None, latitude=28.2282, longitude=112.9388))
        assert result["weather_context"]["sourceType"] == "coordinates"

    def test_weather_context_has_temperature_with_coords(self):
        """Verifies weather context has temperature with coords."""
        fc = _forecast(city=None, source="coordinates",
                       temperature_max=33.5, temperature_min=24.0)
        fake = FakeWeatherClient(forecast=fc)
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state(city=None, latitude=28.2282, longitude=112.9388))
        assert result["weather_context"]["temperatureMax"] == 33.5
        assert result["weather_context"]["temperatureMin"] == 24.0

    def test_user_message_shows_location_label_when_city_is_none(self):
        """Verifies user message shows location label when city is none."""
        fc = _forecast(city=None, source="coordinates", weather_type="rain")
        fake = FakeWeatherClient(forecast=fc)
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state(city=None, latitude=28.2282, longitude=112.9388))
        user_msg = result["tools"]["get_weather"].message_for_user or ""
        assert "当前位置" in user_msg

    def test_agent_message_includes_location_label(self):
        """Verifies agent message includes location label."""
        fc = _forecast(city=None, source="coordinates")
        fake = FakeWeatherClient(forecast=fc)
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state(city=None, latitude=28.2282, longitude=112.9388))
        msg = result["tools"]["get_weather"].message_for_agent or ""
        assert "当前位置" in msg

    def test_coordinates_with_city_preserves_city_in_context(self):
        """When both coords and city are given, city is preserved for display."""
        fc = _forecast(city="长沙", source="coordinates")
        fake = FakeWeatherClient(forecast=fc)
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state(city="长沙", latitude=28.2282, longitude=112.9388))
        assert result["weather_context"]["city"] == "长沙"
        assert result["weather_context"]["sourceType"] == "coordinates"


# ── partial coordinates → skip ─────────────────────────────────────────────


class TestGetWeatherPartialCoordinates:
    """A single coordinate without its pair is treated as no location."""

    def test_latitude_only_skips(self):
        """Verifies latitude only skips."""
        agent = OutfitRecommendationAgent()
        result = agent._get_weather(_state(city=None, latitude=39.9, longitude=None))
        assert result["tools"]["get_weather"].status == "skipped"
        assert result["tools"]["get_weather"].error_code == "LOCATION_NOT_PROVIDED"

    def test_longitude_only_skips(self):
        """Verifies longitude only skips."""
        agent = OutfitRecommendationAgent()
        result = agent._get_weather(_state(city=None, latitude=None, longitude=116.4))
        assert result["tools"]["get_weather"].status == "skipped"
        assert result["tools"]["get_weather"].error_code == "LOCATION_NOT_PROVIDED"

    def test_all_location_fields_none_skips(self):
        """Verifies all location fields none skips."""
        agent = OutfitRecommendationAgent()
        result = agent._get_weather(_state(city=None, latitude=None, longitude=None))
        assert result["tools"]["get_weather"].status == "skipped"
        assert result["tools"]["get_weather"].error_code == "LOCATION_NOT_PROVIDED"


# ── missing city (no coordinates either) ───────────────────────────────────


class TestGetWeatherNoLocation:
    """When request has neither city nor coordinates, weather is skipped."""

    def test_status_is_skipped(self):
        """Verifies status is skipped."""
        agent = OutfitRecommendationAgent()
        result = agent._get_weather(_state(city=None))
        assert result["tools"]["get_weather"].status == "skipped"

    def test_error_code_is_location_not_provided(self):
        """Verifies error code is location not provided."""
        agent = OutfitRecommendationAgent()
        result = agent._get_weather(_state(city=None))
        assert result["tools"]["get_weather"].error_code == "LOCATION_NOT_PROVIDED"

    def test_not_retryable(self):
        """Verifies not retryable."""
        agent = OutfitRecommendationAgent()
        result = agent._get_weather(_state(city=None))
        assert result["tools"]["get_weather"].retryable is False

    def test_data_city_is_none(self):
        """Verifies data city is none."""
        agent = OutfitRecommendationAgent()
        result = agent._get_weather(_state(city=None))
        assert result["weather_context"]["city"] is None

    def test_data_still_has_target_date(self):
        """Verifies data still has target date."""
        agent = OutfitRecommendationAgent()
        result = agent._get_weather(_state(city=None, target_date=date(2026, 7, 1)))
        assert result["weather_context"]["targetDate"] == "2026-07-01"

    def test_agent_message_forbids_inventing_weather(self):
        """Verifies agent message forbids inventing weather."""
        agent = OutfitRecommendationAgent()
        result = agent._get_weather(_state(city=None))
        msg = result["tools"]["get_weather"].message_for_agent or ""
        assert "Do not invent" in msg
        assert "temperature" in msg

    def test_no_provider_called(self):
        """When no location is given, the weather client must not be invoked."""
        fc = _forecast()
        fake = FakeWeatherClient(forecast=fc)
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state(city=None))
        assert result["tools"]["get_weather"].status == "skipped"
        assert result["tools"]["get_weather"].error_code == "LOCATION_NOT_PROVIDED"


# ── provider error ─────────────────────────────────────────────────────────


class TestGetWeatherProviderError:
    """When the weather provider raises, state must carry a failed result."""

    def test_status_is_failed(self):
        """Verifies status is failed."""
        fake = FakeWeatherClient(fail_with=WeatherClientError("timeout"))
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state())
        assert result["tools"]["get_weather"].status == "failed"

    def test_error_code_is_weather_provider_error(self):
        """Verifies error code is weather provider error."""
        fake = FakeWeatherClient(fail_with=WeatherClientError("timeout"))
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state())
        assert result["tools"]["get_weather"].error_code == "WEATHER_PROVIDER_ERROR"

    def test_is_retryable(self):
        """Verifies is retryable."""
        fake = FakeWeatherClient(fail_with=WeatherClientError("DNS failure"))
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state())
        assert result["tools"]["get_weather"].retryable is True

    def test_agent_message_includes_error_detail(self):
        """Verifies agent message includes error detail."""
        fake = FakeWeatherClient(fail_with=WeatherClientError("connection refused"))
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state())
        msg = result["tools"]["get_weather"].message_for_agent or ""
        assert "connection refused" in msg
        assert "Do not invent" in msg

    def test_weather_context_still_has_city(self):
        """Verifies weather context still has city."""
        fake = FakeWeatherClient(fail_with=WeatherClientError("timeout"))
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state(city="杭州"))
        assert result["weather_context"]["city"] == "杭州"

    def test_weather_context_has_no_temperature(self):
        """On failure, weather_context must NOT carry made-up temperature."""
        fake = FakeWeatherClient(fail_with=WeatherClientError("timeout"))
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state())
        assert "temperatureMax" not in result["weather_context"]

    def test_coordinates_error_uses_location_label(self):
        """Verifies coordinates error uses location label."""
        fake = FakeWeatherClient(fail_with=WeatherClientError("timeout"))
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state(city=None, latitude=28.2282, longitude=112.9388))
        msg = result["tools"]["get_weather"].message_for_agent or ""
        assert "当前位置" in msg


# ── forecast unavailable ───────────────────────────────────────────────────


class TestGetWeatherUnavailable:
    """When the provider returns None (city unknown or date too far), skip."""

    def test_status_is_skipped(self):
        """Verifies status is skipped."""
        fake = FakeWeatherClient(forecast=None)
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state())
        assert result["tools"]["get_weather"].status == "skipped"

    def test_error_code_is_weather_not_available(self):
        """Verifies error code is weather not available."""
        fake = FakeWeatherClient(forecast=None)
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state())
        assert result["tools"]["get_weather"].error_code == "WEATHER_NOT_AVAILABLE"

    def test_not_retryable(self):
        """Verifies not retryable."""
        fake = FakeWeatherClient(forecast=None)
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state())
        assert result["tools"]["get_weather"].retryable is False

    def test_agent_message_includes_location_and_date(self):
        """Verifies agent message includes location and date."""
        fake = FakeWeatherClient(forecast=None)
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state(city="拉萨", target_date=date(2026, 12, 25)))
        msg = result["tools"]["get_weather"].message_for_agent or ""
        assert "拉萨" in msg
        assert "2026-12-25" in msg

    def test_weather_context_has_no_temperature(self):
        """Verifies weather context has no temperature."""
        fake = FakeWeatherClient(forecast=None)
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state())
        assert "temperatureMax" not in result["weather_context"]

    def test_coordinates_unavailable_uses_location_label(self):
        """Verifies coordinates unavailable uses location label."""
        fake = FakeWeatherClient(forecast=None)
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state(city=None, latitude=28.2282, longitude=112.9388))
        msg = result["tools"]["get_weather"].message_for_agent or ""
        assert "当前位置" in msg


# ── default date is today ──────────────────────────────────────────────────


class TestGetWeatherDefaultDate:
    """When target_date is None, the node uses today's date."""

    def test_uses_today_when_date_is_none(self):
        """Verifies uses today when date is none."""
        fc = _forecast(forecast_date=date.today())
        fake = FakeWeatherClient(forecast=fc)
        agent = OutfitRecommendationAgent(weather_client=fake)
        result = agent._get_weather(_state(target_date=None))
        assert result["tools"]["get_weather"].status == "success"
        assert result["weather_context"]["targetDate"] == date.today().isoformat()


# ── weather context flows into agent prompt ────────────────────────────────


class TestWeatherContextInPrompt:
    """After _get_weather runs, the prompt must expose the real weather data."""

    def test_prompt_includes_real_weather_context(self):
        """Verifies prompt includes real weather context."""
        fc = _forecast(city="广州", temperature_max=33.0, temperature_min=27.0)
        fake = FakeWeatherClient(forecast=fc)
        agent = OutfitRecommendationAgent(weather_client=fake)
        state = _state(city="广州")
        update = agent._get_weather(state)
        state.update(update)
        state.setdefault("taxonomy", get_clothing_taxonomy())

        messages = agent._agent_loop_messages(state)
        import json
        payload = json.loads(messages[1]["content"])
        wc = payload["weatherContext"]

        assert wc["city"] == "广州"
        assert wc["temperatureMax"] == 33.0
        assert wc["temperatureMin"] == 27.0
        assert wc["weatherType"] == "rain"
        assert wc["source"] == "open-meteo"

    def test_prompt_excludes_temperature_when_not_available(self):
        """On failure the prompt must NOT carry fake temperature."""
        fake = FakeWeatherClient(fail_with=WeatherClientError("boom"))
        agent = OutfitRecommendationAgent(weather_client=fake)
        state = _state()
        update = agent._get_weather(state)
        state.update(update)
        state.setdefault("taxonomy", get_clothing_taxonomy())

        messages = agent._agent_loop_messages(state)
        import json
        payload = json.loads(messages[1]["content"])
        wc = payload["weatherContext"]

        assert "temperatureMax" not in wc
        assert "note" in wc  # guidance for the model

    def test_empty_weather_context_when_node_not_run(self):
        """Without _get_weather, prompt uses empty dict."""
        agent = OutfitRecommendationAgent()
        state = _state()
        state["taxonomy"] = get_clothing_taxonomy()

        messages = agent._agent_loop_messages(state)
        import json
        payload = json.loads(messages[1]["content"])
        assert payload["weatherContext"] == {}

    def test_coordinates_prompt_includes_source_type(self):
        """Verifies coordinates prompt includes source type."""
        fc = _forecast(city=None, source="coordinates", temperature_max=33.5, temperature_min=24.0)
        fake = FakeWeatherClient(forecast=fc)
        agent = OutfitRecommendationAgent(weather_client=fake)
        state = _state(city=None, latitude=28.2282, longitude=112.9388)
        update = agent._get_weather(state)
        state.update(update)
        state.setdefault("taxonomy", get_clothing_taxonomy())

        messages = agent._agent_loop_messages(state)
        import json
        payload = json.loads(messages[1]["content"])
        wc = payload["weatherContext"]

        assert wc["sourceType"] == "coordinates"
        assert wc["temperatureMax"] == 33.5
        assert wc["city"] is None


# ── full graph integration ─────────────────────────────────────────────────


class FakeFinalAnswerLLM:
    """Returns a final JSON answer so the full graph can run to completion."""

    provider_name = "fake"
    model = "fake-model"

    def ensure_configured(self):
        """Matches the real LLM configuration check."""
        return None

    def complete_message(self, messages, *, tools=None, tool_choice=None):
        """Returns a deterministic final assistant message."""
        return {
            "role": "assistant",
            "content": (
                '{"outfit":{"name":"雨天推荐","items":[]},'
                '"recommendationReason":"基于天气数据。",'
                '"weatherReason":"上海下雨28°C，选防水外套。",'
                '"preferenceReason":null,'
                '"missingItems":[],'
                '"userMessage":"今天有雨。"}'
            ),
        }


class TestWeatherInFullGraph:
    """The weather node runs first in the graph and its output propagates."""

    def test_weather_result_in_tools_trace(self):
        """Verifies weather result in tools trace."""
        fc = _forecast()
        fake = FakeWeatherClient(forecast=fc)
        agent = OutfitRecommendationAgent(
            llm=FakeFinalAnswerLLM(),
            weather_client=fake,
        )
        result = agent.run(
            None,
            user_id=uuid4(),
            request=OutfitRecommendationRequest(
                message="下雨穿什么",
                city="上海",
                targetDate=date(2026, 6, 3),
            ),
        )
        assert "get_weather" in result["tools"]
        assert result["tools"]["get_weather"].status == "success"

    def test_raw_model_output_includes_weather_reason(self):
        """Verifies raw model output includes weather reason."""
        fc = _forecast()
        fake = FakeWeatherClient(forecast=fc)
        agent = OutfitRecommendationAgent(
            llm=FakeFinalAnswerLLM(),
            weather_client=fake,
        )
        result = agent.run(
            None,
            user_id=uuid4(),
            request=OutfitRecommendationRequest(
                message="下雨穿什么",
                city="上海",
                targetDate=date(2026, 6, 3),
            ),
        )
        assert "下雨" in result["weatherReason"]

    def test_no_location_full_graph_still_completes(self):
        """When no city or coordinates are provided, graph finishes gracefully."""
        agent = OutfitRecommendationAgent(llm=FakeFinalAnswerLLM())
        result = agent.run(
            None,
            user_id=uuid4(),
            request=OutfitRecommendationRequest(message="穿什么", city=None),
        )
        assert "get_weather" in result["tools"]
        assert result["tools"]["get_weather"].status == "skipped"

    def test_coordinates_full_graph_completes(self):
        """Full graph with coordinates-only lookup finishes successfully."""
        fc = _forecast(city=None, source="coordinates")
        fake = FakeWeatherClient(forecast=fc)
        agent = OutfitRecommendationAgent(
            llm=FakeFinalAnswerLLM(),
            weather_client=fake,
        )
        result = agent.run(
            None,
            user_id=uuid4(),
            request=OutfitRecommendationRequest(
                message="今天穿什么",
                latitude=28.2282,
                longitude=112.9388,
            ),
        )
        assert result["tools"]["get_weather"].status == "success"
