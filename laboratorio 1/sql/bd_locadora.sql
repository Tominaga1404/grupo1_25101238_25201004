DROP DATABASE IF EXISTS bd_locadora;
CREATE DATABASE bd_locadora;
USE bd_locadora;

CREATE TABLE categoria (
    id_categoria INT PRIMARY KEY AUTO_INCREMENT,
    nome_categoria VARCHAR(50) NOT NULL UNIQUE,
    valor_diaria DECIMAL(8,2) NOT NULL
);

CREATE TABLE filial (
    id_filial INT PRIMARY KEY AUTO_INCREMENT,
    nome_filial VARCHAR(100) NOT NULL,
    cidade VARCHAR(100) NOT NULL,
    estado CHAR(2) NOT NULL
);

CREATE TABLE cliente (
    id_cliente INT PRIMARY KEY AUTO_INCREMENT,
    nome VARCHAR(150) NOT NULL,
    cpf CHAR(11) NOT NULL UNIQUE,
    cnh CHAR(11) NOT NULL UNIQUE,
    telefone VARCHAR(20) NOT NULL,
    email VARCHAR(100) NOT NULL
);

CREATE TABLE veiculo (
    id_veiculo INT PRIMARY KEY AUTO_INCREMENT,
    modelo VARCHAR(100) NOT NULL,
    placa VARCHAR(7) NOT NULL UNIQUE,
    ano INT NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'Disponível',
    id_categoria INT NOT NULL,
    CONSTRAINT fk_veiculo_categoria FOREIGN KEY (id_categoria) REFERENCES categoria(id_categoria)
);

CREATE TABLE locacao (
    id_locacao INT PRIMARY KEY AUTO_INCREMENT,
    data_retirada DATETIME NOT NULL,
    data_prevista_devolucao DATETIME NOT NULL,
    data_real_devolucao DATETIME NULL,
    valor_total DECIMAL(10,2) NULL,
    id_cliente INT NOT NULL,
    id_veiculo INT NOT NULL,
    id_filial_retirada INT NOT NULL,
    id_filial_devolucao INT NOT NULL,
    CONSTRAINT fk_locacao_cliente FOREIGN KEY (id_cliente) REFERENCES cliente(id_cliente),
    CONSTRAINT fk_locacao_veiculo FOREIGN KEY (id_veiculo) REFERENCES veiculo(id_veiculo),
    CONSTRAINT fk_locacao_filial_retirada FOREIGN KEY (id_filial_retirada) REFERENCES filial(id_filial),
    CONSTRAINT fk_locacao_filial_devolucao FOREIGN KEY (id_filial_devolucao) REFERENCES filial(id_filial)
);

CREATE TABLE manutencao (
    id_manutencao INT PRIMARY KEY AUTO_INCREMENT,
    data_manutencao DATE NOT NULL,
    descricao TEXT NOT NULL,
    custo DECIMAL(8,2) NOT NULL,
    id_veiculo INT NOT NULL,
    CONSTRAINT fk_manutencao_veiculo FOREIGN KEY (id_veiculo) REFERENCES veiculo(id_veiculo)
);

-- ETAPA 5

INSERT INTO categoria (id_categoria, nome_categoria, valor_diaria) VALUES
(1, 'Econômico', 100.00),
(2, 'Intermediário', 150.00),
(3, 'SUV', 220.00),
(4, 'Luxo', 350.00),
(5, 'Utilitário', 280.00);

INSERT INTO filial (id_filial, nome_filial, cidade, estado) VALUES
(1, 'Filial Centro', 'Brasília', 'DF'),
(2, 'Filial Aeroporto', 'Brasília', 'DF'),
(3, 'Filial Asa Sul', 'Brasília', 'DF'),
(4, 'Filial Paulista', 'São Paulo', 'SP'),
(5, 'Filial Salgado Filho', 'Porto Alegre', 'RS');

INSERT INTO cliente (id_cliente, nome, cpf, cnh, telefone, email) VALUES
(1, 'Ana Souza', '11122233344', '12345678901', '(61) 98888-1111', 'ana.souza@email.com'),
(2, 'Carlos Lima', '22233344455', '23456789012', '(61) 97777-2222', 'carlos.lima@email.com'),
(3, 'Mariana Costa', '33344455666', '34567890123', '(61) 96666-3333', 'mariana.costa@email.com'),
(4, 'João Pereira', '44455566777', '45678901234', '(11) 95555-4444', 'joao.pereira@email.com'),
(5, 'Beatriz Alves', '55566677888', '56789012345', '(51) 94444-5555', 'beatriz.alves@email.com');

INSERT INTO veiculo (id_veiculo, modelo, placa, ano, status, id_categoria) VALUES
(1, 'Fiat Argo', 'ABC1A23', 2023, 'Alugado', 1),
(2, 'Chevrolet Onix', 'BCD2B34', 2022, 'Disponível', 1),
(3, 'Jeep Compass', 'CDE3C45', 2024, 'Disponível', 3),
(4, 'Toyota Corolla', 'DEF4D56', 2023, 'Alugado', 4),
(5, 'Renault Duster', 'EFG5E67', 2021, 'Disponível', 3);

INSERT INTO locacao (id_locacao, data_retirada, data_prevista_devolucao, data_real_devolucao, valor_total, id_cliente, id_veiculo, id_filial_retirada, id_filial_devolucao) VALUES
(1, '2026-09-01 10:00:00', '2026-09-05 10:00:00', NULL, NULL, 1, 1, 1, 2),
(2, '2026-08-20 14:00:00', '2026-08-25 14:00:00', '2026-08-26 16:00:00', 1320.00, 2, 4, 2, 2),
(3, '2026-09-02 09:00:00', '2026-09-06 09:00:00', '2026-09-06 08:30:00', 880.00, 1, 3, 3, 3),
(4, '2026-09-03 11:00:00', '2026-09-10 11:00:00', NULL, NULL, 3, 5, 1, 3),
(5, '2026-08-10 08:00:00', '2026-08-12 08:00:00', '2026-08-12 08:00:00', 300.00, 4, 2, 4, 4);

INSERT INTO manutencao (id_manutencao, data_manutencao, descricao, custo, id_veiculo) VALUES
(1, '2026-07-15', 'Troca de óleo e filtros', 250.00, 1),
(2, '2026-07-20', 'Alinhamento e balanceamento', 180.00, 2),
(3, '2026-08-01', 'Troca de pastilhas de freio', 450.00, 4),
(4, '2026-08-05', 'Revisão geral dos 20.000 km', 600.00, 3),
(5, '2026-08-15', 'Reparo no sistema de suspensão', 850.00, 5);

-- CONSULTAS

-- Locações em aberto
SELECT l.id_locacao, c.nome AS cliente, v.modelo, l.data_retirada, l.data_prevista_devolucao
FROM locacao l
JOIN cliente c ON l.id_cliente = c.id_cliente
JOIN veiculo v ON l.id_veiculo = v.id_veiculo
WHERE l.data_real_devolucao IS NULL;

-- Veículos disponíveis agrupados por categoria
SELECT c.nome_categoria, v.modelo, v.placa, v.ano, v.status
FROM veiculo v
JOIN categoria c ON v.id_categoria = c.id_categoria
WHERE v.status = 'Disponível'
ORDER BY c.nome_categoria, v.modelo;

-- Cliente que mais realizou locações (COUNT + GROUP BY)
SELECT cl.id_cliente, cl.nome, COUNT(l.id_locacao) AS total_locacoes
FROM cliente cl
JOIN locacao l ON cl.id_cliente = l.id_cliente
GROUP BY cl.id_cliente, cl.nome
ORDER BY total_locacoes DESC
LIMIT 1;

-- Faturamento total por filial de retirada (SUM + JOIN + GROUP BY)
SELECT f.id_filial, f.nome_filial, SUM(l.valor_total) AS faturamento_total
FROM filial f
JOIN locacao l ON f.id_filial = l.id_filial_retirada
WHERE l.valor_total IS NOT NULL
GROUP BY f.id_filial, f.nome_filial;

-- Locações com atraso na devolução
SELECT l.id_locacao, cl.nome AS cliente, v.modelo, l.data_prevista_devolucao, l.data_real_devolucao
FROM locacao l
JOIN cliente cl ON l.id_cliente = cl.id_cliente
JOIN veiculo v ON l.id_veiculo = v.id_veiculo
WHERE l.data_real_devolucao > l.data_prevista_devolucao;

-- Custo total de manutenção por veículo
SELECT v.id_veiculo, v.modelo, v.placa, SUM(m.custo) AS custo_total_manutencao
FROM veiculo v
JOIN manutencao m ON v.id_veiculo = m.id_veiculo
GROUP BY v.id_veiculo, v.modelo, v.placa;
