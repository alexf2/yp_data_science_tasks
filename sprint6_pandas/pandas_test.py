import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

"""
s = pd.Series([1, 3.5, 'text'])  # Series
df = pd.DataFrame({'A': [1, 2], 'B': ['x', 'y']})  # DataFrame

print('-' * 5, 'info')
print(df.info())
print('-' * 5, 'dtypes')
print(df.dtypes)
print('-' * 5, 'shape')
print(df.shape)
print('-' * 5, 'columns')
print(df.columns)
print('-' * 5, 'head')
print(df.head())
print('-' * 5, 'describe')
print(df.describe())
print('-' * 5, 'index')
print(df.index)
print(df.index.name)
print(df.index.is_unique)



# Создадим датафрейм из словаря
data = {
    'product_id': [1, 2, 3, 4],
    'product_name': ['Яблоки', 'Бананы', 'Вишня', 'Груши'],
    'quantity': [10, 5, 20, 15],
    'price_per_unit': [2.5, 1.2, 0.8, 3.0]
}

df = pd.DataFrame(data)

# Выведем столбец quantity
print(df['quantity'])
"""

"""
# Создаём небольшой датафрейм с пропусками
df = pd.DataFrame({'column_int': [1, 2, None],
                   'column_float': [0.5, None, 5.75]})

# Выводим датафрейм на экран
print(df)

df = pd.DataFrame({
    'column_int': pd.Series([1, 2, None], dtype="Int64"),
    'column_float': [0.5, None, 5.75]
})

print(df)
print(type(df['column_int'][2]))
"""

# data = {
#     'product': ['Хлеб', 'Молоко', 'Сыр', 'Хлеб', 'Сыр'],
#     'count': [20, 30, 15, 25, 20],
#     'price': [50, 60, 200, 55, 210]
# }
# df = pd.DataFrame(data)
# print(df)


# # The `people` DataFrame
# people = pd.DataFrame({'FirstName': ['John', 'Jane'],
#                        'LastName': ['Doe', 'Austen'],
#                        'BloodType': ['A-', 'B+'],
#                        'Weight': [90, 64]})

# print(people)

# # Use `melt()` on the `people` DataFrame
# print(pd.melt(people, id_vars=['FirstName', 'LastName'], var_name='measurements'))


# Создаём датафрейм с названиями фруктов
fruits = pd.DataFrame({
    'fruit_id': [1, 2, 3],
    'fruit_name': ['Яблоки', 'Груши', 'Бананы']
})

# Создаём датафрейм с продажами фруктов
# fruits_sale = pd.DataFrame({
#     'cheque_id': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
#     'fruit_id': [1, 2, 3, 3, 2, 1, 2, 1, 3, 3, 1, 2],
#     'amount': [11, 22, 26, 18, 12, 34, 57, 15, 36, 25, 30, 31]
# })

# sum_amount = fruits_sale.groupby('fruit_id')['amount'].sum()

# print(type(sum_amount))
# print("Индекс:", sum_amount.index)
# print("Индекс:", sum_amount.index.name)
# print(sum_amount)


# Загружаем bank_information.csv в переменную df
df = pd.read_csv('https://code.s3.yandex.net/datasets/bank_information.csv')

# Строим гистограммы по всем данным датафрейма
df.hist(figsize=(12, 10))
plt.tight_layout()
plt.show()
