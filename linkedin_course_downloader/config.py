# Configuration file
import os

# Select the course or courses (comma between)
COURSES = [
'web-servers-and-apis-using-c-plus-plus'
]

# Connection details
DOWNLOAD_STREAMS = 1
USERNAME = 'your_linkedin_user'
PASSWORD = 'your_password'

# EDIT IF YOU NEED TO
BASE_DOWNLOAD_PATH = os.path.join(os.path.dirname(__file__), "downloads")
USE_PROXY = False
PROXY = "http://127.0.0.1:8888" if USE_PROXY else None
