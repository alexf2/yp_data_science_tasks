import numpy as np
import pandas as pd
from sklearn.datasets import make_regression

# Генерация базовых данных
X, y = make_regression(n_samples=200,
                       n_features=1,
                       noise=50,
                       random_state=42)

# Преобразуем в DataFrame для удобства
X = pd.DataFrame(X, columns=['feature'])
y = pd.Series(y, name='target')

print(X)
# print(y)
