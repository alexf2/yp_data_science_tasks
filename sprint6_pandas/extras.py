# https://colab.research.google.com/drive/1OysvPL_bml64UF5DgFluS5AAUVmri9Hj?usp=sharing


def task1():
    lst = []
    str = 'abc'

    print(id(lst), id(str))

    lst.append(4)
    str += 'd'

    print(id(lst), id(str))
    # тут id у list не изменился, так как это мутабельный тип
    # id у string поменялся, так как это немутабельный тип, а унарный + возвращает новую строку


# task1()


def task2():
    in_result = input('Введите целые числа и слова через пробелы>')
    if not in_result:
        print('Пустая строка')
    else:
        words = []
        numbers = []
        for item in in_result.split():
            if item.isdigit():
                numbers.append(int(item))
            else:
                words.append(item)

        print(words)
        print(numbers)


# task2()


def task3(phrase):
    if not phrase:
        return ''

    result = []
    for word in reversed(phrase.split()):
        result.append(word[::-1] if len(word) > 4 else word)

    return ' '.join(result)


test_str = 'Are you familiar with other software for manipulating tabular data? Learn the pandas-equivalent'

# print(test_str, '-->', task3(test_str))


def task4():
    acc = []
    while True:
        num = input('Вводте целые числа>')
        try:
            value = int(num)
        except ValueError:
            continue
        if value < 0:
            break
        acc.append(value)

    return tuple([0] + sorted(set(acc), reverse=True))


# print(task4())

def task5(numbers):
    if not numbers:
        return 0, 0

    sum = 0
    mul = 1
    for item in numbers:
        sum += item
        mul *= item

    return sum, mul


result_sim, result_mul = task5([2, 4, 5, 1])
print(result_sim, result_mul)


def task6():
    dic = {
        'Иван': [4, 5, 4, 3, 4, 5],
        'Петр': [5, 5, 5, 4, 5, 5],
        'Сергей': [3, 4, 4, 2, 3, 4],
        'Мария': [5, 5, 5, 5, 5, 5],
        'Анна': [4, 4, 4, 4, 4, 4],
        'Ольга': [5, 4, 5, 4, 5, 4],
        'Дмитрий': [3, 3, 4, 2, 3, 3],
        'Елена': [4, 5, 4, 4, 5],
    }

    def add_student(name, students_book, grades=None):
        if grades is None:
            grades = []
        if name in students_book:
            student_grades = students_book[name]
            student_grades.extend(grades)
            return student_grades

        students_book[name] = grades[:]
        return students_book[name]

    def get_avg_grade(name, students_book):
        if name in students_book:
            return sum(students_book[name]) / len(students_book[name])

        return 0

    def get_best_student(students_book):
        best_student_name = None
        best_avg = 0

        for name, grades in students_book.items():
            curr_avg = sum(grades) / len(grades)
            if curr_avg > best_avg:
                best_avg = curr_avg
                best_student_name = name

        return best_student_name, best_avg

    add_student('Адам', dic, [5, 5, 3, 2, 4])
    add_student('Ольга', dic, [4, 4])
    print(dic)
    print(get_avg_grade('Ольга', dic))
    print(get_avg_grade('Сергей', dic))
    print(get_best_student(dic))


task6()


def task7():
    ph1 = input('Введите первую фразу>')
    ph2 = input('Введите вторую фразу>')

    words1 = set([word.lower() for word in ph1.split()])
    words2 = set([word.lower() for word in ph2.split()])

    print(list(sorted(words1 & words2)))
    print(list(sorted(words1 | words2)))
    print(list(sorted(words1 - words2)))


task7()
