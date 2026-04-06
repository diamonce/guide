-- ─────────────────────────────────────────
-- shopdb schema + seed data
-- ─────────────────────────────────────────

USE shopdb;

CREATE TABLE IF NOT EXISTS customers (
    id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(255)        NOT NULL,
    email      VARCHAR(255)        NOT NULL UNIQUE,
    created_at TIMESTAMP           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS products (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    sku         VARCHAR(100)        NOT NULL UNIQUE,
    name        VARCHAR(255)        NOT NULL,
    price       DECIMAL(10,2)       NOT NULL,
    stock       INT                 NOT NULL DEFAULT 0,
    created_at  TIMESTAMP           NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS orders (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    customer_id BIGINT UNSIGNED     NOT NULL,
    total       DECIMAL(10,2)       NOT NULL,
    status      ENUM('pending','paid','shipped','cancelled') NOT NULL DEFAULT 'pending',
    created_at  TIMESTAMP           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_customer_id (customer_id),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at),
    FOREIGN KEY (customer_id) REFERENCES customers(id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS order_items (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_id    BIGINT UNSIGNED     NOT NULL,
    product_id  BIGINT UNSIGNED     NOT NULL,
    quantity    INT                 NOT NULL,
    unit_price  DECIMAL(10,2)       NOT NULL,
    INDEX idx_order_id (order_id),
    FOREIGN KEY (order_id)   REFERENCES orders(id),
    FOREIGN KEY (product_id) REFERENCES products(id)
) ENGINE=InnoDB;

-- ─────────────────────────────────────────
-- Seed data
-- ─────────────────────────────────────────

INSERT INTO customers (name, email) VALUES
    ('Alice Smith',   'alice@example.com'),
    ('Bob Jones',     'bob@example.com'),
    ('Carol White',   'carol@example.com'),
    ('Dave Brown',    'dave@example.com'),
    ('Eve Davis',     'eve@example.com');

INSERT INTO products (sku, name, price, stock) VALUES
    ('SKU-001', 'Laptop Pro 15',   1299.99, 50),
    ('SKU-002', 'Wireless Mouse',    29.99, 200),
    ('SKU-003', 'USB-C Hub',         49.99, 150),
    ('SKU-004', 'Mechanical Keyboard',89.99, 75),
    ('SKU-005', 'Monitor 27"',      399.99, 30);

INSERT INTO orders (customer_id, total, status) VALUES
    (1, 1329.98, 'paid'),
    (2,   49.99, 'shipped'),
    (3,  489.98, 'pending'),
    (1,   89.99, 'paid'),
    (4, 1299.99, 'cancelled');

INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
    (1, 1, 1, 1299.99),
    (1, 2, 1,   29.99),
    (2, 3, 1,   49.99),
    (3, 4, 1,   89.99),
    (3, 5, 1,  399.99),
    (4, 4, 1,   89.99),
    (5, 1, 1, 1299.99);
