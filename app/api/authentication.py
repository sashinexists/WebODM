from rest_framework_simplejwt.authentication import JWTAuthentication


class JSONWebTokenAuthenticationQS(JWTAuthentication):
    def authenticate(self, request):
        # Get JWT from query string instead of header
        raw_token = request.query_params.get('jwt')
        if raw_token is None:
            return None

        validated_token = self.get_validated_token(raw_token)
        return self.get_user(validated_token), validated_token