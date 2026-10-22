import pandas as pd
from db import get_connection

conn = get_connection()
cur = conn.cursor()
cur.execute("SELECT * FROM plans")
columns = [col[0] for col in cur.description]
df = pd.DataFrame(cur.fetchall(), columns=columns)
print(df)

cur.close()
conn.close()