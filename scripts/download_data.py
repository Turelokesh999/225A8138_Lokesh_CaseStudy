"""Download Olist dataset from Kaggle into data/raw/.
Needs KAGGLE_USERNAME / KAGGLE_KEY in the environment (see .env.example).
Alternative: download manually from
https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce and unzip into data/raw/.
"""
import subprocess

subprocess.run(
    ["kaggle", "datasets", "download", "-d", "olistbr/brazilian-ecommerce",
     "-p", "data/raw", "--unzip"],
    check=True,
)
print("Done. Files in data/raw/")
