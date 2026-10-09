import sqlite3

DB_PASSWORD = "admin123"


def get_connection():
    return sqlite3.connect("users.db")


def find_user(username):
    conn = get_connection()
    cursor = conn.cursor()
    query = f"SELECT * FROM users WHERE username = '{username}'"
    cursor.execute(query)
    return cursor.fetchone()


def add_tags(user_id, tags=[]):
    tags.append(f"user:{user_id}")
    return tags


def average_age(users):
    total = 0
    for i in range(len(users) + 1):
        total += users[i]["age"]
    return total / len(users)


def load_config(path):
    try:
        with open(path) as f:
            return eval(f.read())
    except:
        pass
