import time

from outlook_internal.session import SessionSnapshot, decode_jwt_payload


def test_decode_jwt_payload_tolerates_missing_token():
  assert decode_jwt_payload(None) == {}
  assert decode_jwt_payload("not-a-jwt") == {}


def test_session_expiry_uses_decoded_payload():
  snapshot = SessionSnapshot.from_dict(
    {
      "base_url": "https://outlook.cloud.microsoft",
      "account": "navon.mitmpl2024@learner.manipal.edu",
      "authorization": "Bearer fake",
      "x_anchormailbox": "PUID:test@tenant",
      "x_owa_sessionid": "session",
      "token_payload": {"exp": int(time.time()) + 600, "tid": "tenant"},
    }
  )

  assert snapshot.tenant_id == "tenant"
  assert snapshot.seconds_until_expiry() > 0

