CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(255) UNIQUE NOT NULL,
    surname VARCHAR(255),
    givenname VARCHAR(255),
    email VARCHAR(255),
    password VARCHAR(255),
    description TEXT,
    mobile VARCHAR(255),
    phone VARCHAR(255)
);
