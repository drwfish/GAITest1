"""Seed the evaluation SQLite database with test data.

Run this script to create/recreate the eval.db file with test tables.
"""

import sqlite3
from pathlib import Path

DB_PATH = Path(__file__).parent / "eval.db"


def seed():
    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()

    # Create employees table
    c.execute("DROP TABLE IF EXISTS employees")
    c.execute("""
        CREATE TABLE employees (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            department TEXT NOT NULL,
            salary REAL NOT NULL,
            hire_date TEXT NOT NULL
        )
    """)
    employees = [
        (1, "Alice Johnson", "Engineering", 125000, "2020-03-15"),
        (2, "Bob Smith", "Engineering", 115000, "2021-06-01"),
        (3, "Carol Williams", "Engineering", 130000, "2019-01-10"),
        (4, "David Brown", "Marketing", 95000, "2022-02-20"),
        (5, "Eve Davis", "Marketing", 88000, "2023-07-05"),
        (6, "Frank Miller", "Sales", 92000, "2021-09-12"),
        (7, "Grace Wilson", "Sales", 105000, "2020-11-03"),
        (8, "Henry Moore", "Sales", 98000, "2022-04-18"),
        (9, "Iris Taylor", "HR", 85000, "2023-01-25"),
        (10, "Jack Anderson", "HR", 82000, "2022-08-30"),
        (11, "Karen Thomas", "Finance", 110000, "2020-05-22"),
        (12, "Leo Jackson", "Finance", 105000, "2021-03-14"),
        (13, "Mia White", "Engineering", 140000, "2018-07-01"),
        (14, "Noah Harris", "Engineering", 120000, "2022-10-11"),
        (15, "Olivia Martin", "Marketing", 91000, "2023-04-03"),
        (16, "Peter Garcia", "Product", 118000, "2021-01-20"),
        (17, "Quinn Robinson", "Product", 112000, "2022-06-15"),
        (18, "Rachel Clark", "Engineering", 135000, "2019-11-28"),
        (19, "Sam Lewis", "Sales", 96000, "2023-08-10"),
        (20, "Tina Lee", "Finance", 108000, "2021-12-05"),
    ]
    c.executemany("INSERT INTO employees VALUES (?, ?, ?, ?, ?)", employees)

    # Create products table
    c.execute("DROP TABLE IF EXISTS products")
    c.execute("""
        CREATE TABLE products (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            price REAL NOT NULL,
            stock INTEGER NOT NULL
        )
    """)
    products = [
        (1, "Laptop Pro 15", "Electronics", 1299.99, 45),
        (2, "Wireless Mouse", "Electronics", 29.99, 200),
        (3, "USB-C Hub", "Electronics", 49.99, 150),
        (4, "Standing Desk", "Furniture", 599.99, 30),
        (5, "Ergonomic Chair", "Furniture", 449.99, 25),
        (6, "Monitor 27-inch", "Electronics", 379.99, 60),
        (7, "Mechanical Keyboard", "Electronics", 89.99, 120),
        (8, "Desk Lamp", "Furniture", 45.99, 80),
        (9, "Webcam HD", "Electronics", 69.99, 90),
        (10, "Noise-Canceling Headphones", "Electronics", 249.99, 55),
        (11, "Whiteboard", "Office Supplies", 34.99, 40),
        (12, "Notebook Pack (3)", "Office Supplies", 12.99, 300),
        (13, "Printer Laser", "Electronics", 299.99, 20),
        (14, "Cable Management Kit", "Office Supplies", 19.99, 100),
        (15, "External SSD 1TB", "Electronics", 89.99, 70),
        (16, "Laptop Stand", "Furniture", 39.99, 65),
        (17, "Mouse Pad XL", "Office Supplies", 14.99, 180),
        (18, "Power Strip Smart", "Electronics", 34.99, 95),
        (19, "File Cabinet", "Furniture", 189.99, 15),
        (20, "Wireless Charger", "Electronics", 24.99, 110),
    ]
    c.executemany("INSERT INTO products VALUES (?, ?, ?, ?, ?)", products)

    # Create orders table
    c.execute("DROP TABLE IF EXISTS orders")
    c.execute("""
        CREATE TABLE orders (
            id INTEGER PRIMARY KEY,
            customer_name TEXT NOT NULL,
            product_id INTEGER NOT NULL,
            quantity INTEGER NOT NULL,
            order_date TEXT NOT NULL,
            total REAL NOT NULL,
            FOREIGN KEY (product_id) REFERENCES products(id)
        )
    """)
    orders = [
        (1, "Acme Corp", 1, 5, "2025-01-05", 6499.95),
        (2, "TechStart Inc", 2, 20, "2025-01-08", 599.80),
        (3, "Global Retail", 4, 10, "2025-01-10", 5999.90),
        (4, "Acme Corp", 6, 8, "2025-01-12", 3039.92),
        (5, "DataFlow LLC", 10, 15, "2025-01-15", 3749.85),
        (6, "CloudNine Systems", 1, 3, "2025-01-18", 3899.97),
        (7, "TechStart Inc", 7, 25, "2025-01-20", 2249.75),
        (8, "Global Retail", 5, 5, "2025-01-22", 2249.95),
        (9, "DataFlow LLC", 3, 10, "2025-01-25", 499.90),
        (10, "Acme Corp", 15, 12, "2025-01-28", 1079.88),
        (11, "CloudNine Systems", 9, 8, "2025-02-01", 559.92),
        (12, "TechStart Inc", 13, 2, "2025-02-05", 599.98),
        (13, "Global Retail", 2, 50, "2025-02-08", 1499.50),
        (14, "DataFlow LLC", 6, 4, "2025-02-10", 1519.96),
        (15, "Acme Corp", 8, 10, "2025-02-12", 459.90),
        (16, "CloudNine Systems", 4, 2, "2024-12-05", 1199.98),
        (17, "TechStart Inc", 5, 3, "2024-12-10", 1349.97),
        (18, "Global Retail", 1, 1, "2024-12-15", 1299.99),
        (19, "DataFlow LLC", 7, 5, "2024-12-20", 449.95),
        (20, "Acme Corp", 10, 2, "2024-12-28", 499.98),
    ]
    c.executemany("INSERT INTO orders VALUES (?, ?, ?, ?, ?, ?)", orders)

    conn.commit()
    conn.close()
    print(f"Database seeded at {DB_PATH}")


if __name__ == "__main__":
    seed()
